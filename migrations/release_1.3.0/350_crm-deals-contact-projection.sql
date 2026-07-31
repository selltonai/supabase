-- ============================================================
-- Migration: 345_crm-deals-contact-projection
-- Date:      2026-07-16
-- Purpose:   Project contact pipeline progress into authoritative deals.
-- Projects:  selltonai-database/supabase (owner), selltonai-modal and
--            selltonai (existing contact-stage producers).
-- Contract:  Additive. The projection is forward-only, never writes to
--            contacts, never auto-wins, and isolates failures from contact writes.
-- Depends:   344_crm-deals-foundation.sql
-- ============================================================

CREATE TABLE IF NOT EXISTS public.crm_deal_projection_failures (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id TEXT NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  contact_id UUID REFERENCES public.contacts(id) ON DELETE SET NULL,
  contact_stage TEXT,
  error_code TEXT,
  error_message TEXT NOT NULL,
  resolved_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_crm_deal_projection_failures_unresolved
  ON public.crm_deal_projection_failures (organization_id, created_at DESC)
  WHERE resolved_at IS NULL;

ALTER TABLE public.crm_deal_projection_failures ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.crm_deal_projection_failures FROM anon, authenticated;
GRANT ALL ON TABLE public.crm_deal_projection_failures TO service_role;

CREATE OR REPLACE FUNCTION public.map_contact_stage_to_deal_stage(p_stage TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
  SELECT CASE UPPER(COALESCE(p_stage, ''))
    WHEN 'LEAD' THEN 'LEAD'
    WHEN 'REENGAGEMENT' THEN 'LEAD'
    WHEN 'APPOINTMENT_REQUESTED' THEN 'MEETING_REQUESTED'
    WHEN 'APPOINTMENT_CANCELLED' THEN 'MEETING_REQUESTED'
    WHEN 'APPOINTMENT_SCHEDULED' THEN 'MEETING_BOOKED'
    WHEN 'PRESENTATION_SCHEDULED' THEN 'PRESENTATION'
    WHEN 'CONTRACT_NEGOTIATIONS' THEN 'NEGOTIATION'
    WHEN 'AGREEMENT_IN_PRINCIPLE' THEN 'AGREEMENT'
    WHEN 'CLOSED_LOST' THEN 'LOST'
    WHEN 'NOT_INTERESTED' THEN 'LOST'
    ELSE NULL
  END;
$$;

CREATE OR REPLACE FUNCTION public.crm_deal_stage_level(p_stage TEXT)
RETURNS INTEGER
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
  SELECT CASE UPPER(COALESCE(p_stage, ''))
    WHEN 'LOST' THEN 0
    WHEN 'LEAD' THEN 1
    WHEN 'MEETING_REQUESTED' THEN 2
    WHEN 'MEETING_BOOKED' THEN 3
    WHEN 'PRESENTATION' THEN 4
    WHEN 'NEGOTIATION' THEN 5
    WHEN 'AGREEMENT' THEN 6
    WHEN 'WON' THEN 7
    ELSE -1
  END;
$$;

CREATE OR REPLACE FUNCTION public.project_contact_to_crm_deal(p_contact_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_contact public.contacts;
  v_company_id UUID;
  v_company_name TEXT;
  v_company_owner_id TEXT;
  v_deal_stage TEXT;
  v_deal public.deals;
  v_source_campaign_id UUID;
  v_campaign_owner_id TEXT;
  v_default_amount NUMERIC(14, 2);
  v_default_currency TEXT := 'USD';
  v_deal_found BOOLEAN := FALSE;
  v_other_active_contact_exists BOOLEAN;
  v_replacement_contact_id UUID;
BEGIN
  SELECT *
  INTO v_contact
  FROM public.contacts
  WHERE id = p_contact_id;

  IF NOT FOUND OR v_contact.pipeline_stage IS NULL THEN
    RETURN NULL;
  END IF;

  v_deal_stage := public.map_contact_stage_to_deal_stage(v_contact.pipeline_stage);

  -- CLOSED_WON deliberately maps to NULL: won is a manual-only deal decision.
  IF v_deal_stage IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT cc.company_id, c.name, c.assigned_to_user_id
  INTO v_company_id, v_company_name, v_company_owner_id
  FROM public.company_contacts cc
  JOIN public.companies c
    ON c.id = cc.company_id
   AND c.organization_id = cc.organization_id
  WHERE cc.contact_id = v_contact.id
    AND cc.organization_id = v_contact.organization_id
  ORDER BY cc.created_at DESC NULLS LAST, cc.id DESC
  LIMIT 1;

  IF v_company_id IS NULL THEN
    RETURN NULL;
  END IF;

  -- Attribution is only accepted when there is exactly one campaign candidate.
  -- This avoids silently calling an arbitrary latest campaign the source.
  SELECT MAX(candidate.campaign_id::TEXT)::UUID, MAX(candidate.user_id)
  INTO v_source_campaign_id, v_campaign_owner_id
  FROM (
    SELECT DISTINCT cp.id AS campaign_id, cp.user_id
    FROM public.campaign_companies cc
    JOIN public.campaigns cp
      ON cp.id = cc.campaign_id
     AND cp.organization_id = cc.organization_id
    WHERE cc.company_id = v_company_id
      AND cc.organization_id = v_contact.organization_id
  ) candidate
  HAVING COUNT(*) = 1;

  SELECT os.default_deal_amount, COALESCE(os.default_deal_currency, 'USD')
  INTO v_default_amount, v_default_currency
  FROM public.organization_settings os
  WHERE os.organization_id = v_contact.organization_id;

  -- Assignment columns are soft references in several legacy producers. Only
  -- organization members may become deal owners.
  IF v_contact.assigned_to_user_id IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM public.user_organizations uo
    WHERE uo.organization_id = v_contact.organization_id
      AND uo.user_id = v_contact.assigned_to_user_id
  ) THEN
    v_contact.assigned_to_user_id := NULL;
  END IF;

  IF v_company_owner_id IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM public.user_organizations uo
    WHERE uo.organization_id = v_contact.organization_id
      AND uo.user_id = v_company_owner_id
  ) THEN
    v_company_owner_id := NULL;
  END IF;

  IF v_campaign_owner_id IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM public.user_organizations uo
    WHERE uo.organization_id = v_contact.organization_id
      AND uo.user_id = v_campaign_owner_id
  ) THEN
    v_campaign_owner_id := NULL;
  END IF;

  SELECT *
  INTO v_deal
  FROM public.deals d
  WHERE d.organization_id = v_contact.organization_id
    AND d.company_id = v_company_id
    AND d.closed_at IS NULL
  FOR UPDATE;

  v_deal_found := FOUND;

  IF v_deal_stage = 'LOST' THEN
    IF NOT v_deal_found THEN
      RETURN NULL;
    END IF;

    SELECT other_contact.id
    INTO v_replacement_contact_id
    FROM public.company_contacts cc
    JOIN public.contacts other_contact
      ON other_contact.id = cc.contact_id
     AND other_contact.organization_id = cc.organization_id
    WHERE cc.company_id = v_company_id
      AND cc.organization_id = v_contact.organization_id
      AND other_contact.id <> v_contact.id
      AND public.map_contact_stage_to_deal_stage(other_contact.pipeline_stage) IN (
        'LEAD',
        'MEETING_REQUESTED',
        'MEETING_BOOKED',
        'PRESENTATION',
        'NEGOTIATION',
        'AGREEMENT'
      )
    ORDER BY public.crm_deal_stage_level(
      public.map_contact_stage_to_deal_stage(other_contact.pipeline_stage)
    ) DESC,
      GREATEST(other_contact.stage_updated_at, other_contact.last_incoming_email_at) DESC NULLS LAST,
      other_contact.id
    LIMIT 1;

    v_other_active_contact_exists := v_replacement_contact_id IS NOT NULL;

    IF v_other_active_contact_exists AND v_deal.primary_contact_id = v_contact.id THEN
      PERFORM set_config('app.crm_actor', 'system', TRUE);
      PERFORM set_config('app.crm_actor_user_id', '', TRUE);
      PERFORM set_config('app.crm_contact_id', v_contact.id::TEXT, TRUE);

      UPDATE public.deals
      SET primary_contact_id = v_replacement_contact_id
      WHERE id = v_deal.id
      RETURNING * INTO v_deal;
    END IF;

    IF NOT v_other_active_contact_exists THEN
      PERFORM set_config('app.crm_actor', 'system', TRUE);
      PERFORM set_config('app.crm_actor_user_id', '', TRUE);
      PERFORM set_config('app.crm_contact_id', v_contact.id::TEXT, TRUE);

      UPDATE public.deals
      SET stage = 'LOST',
          stage_contact_id = v_contact.id
      WHERE id = v_deal.id
      RETURNING * INTO v_deal;
    END IF;

    RETURN v_deal.id;
  END IF;

  IF NOT v_deal_found THEN
    PERFORM set_config('app.crm_actor', 'system', TRUE);
    PERFORM set_config('app.crm_actor_user_id', '', TRUE);
    PERFORM set_config('app.crm_contact_id', v_contact.id::TEXT, TRUE);

    INSERT INTO public.deals (
      organization_id,
      company_id,
      primary_contact_id,
      stage_contact_id,
      source_campaign_id,
      owner_user_id,
      name,
      stage,
      amount,
      currency,
      creation_source,
      last_activity_at
    ) VALUES (
      v_contact.organization_id,
      v_company_id,
      v_contact.id,
      v_contact.id,
      v_source_campaign_id,
      COALESCE(v_contact.assigned_to_user_id, v_company_owner_id, v_campaign_owner_id),
      v_company_name,
      v_deal_stage,
      v_default_amount,
      COALESCE(v_default_currency, 'USD'),
      'automatic',
      COALESCE(GREATEST(v_contact.stage_updated_at, v_contact.last_incoming_email_at), NOW())
    )
    ON CONFLICT (organization_id, company_id) WHERE closed_at IS NULL
    DO NOTHING
    RETURNING * INTO v_deal;

    IF v_deal.id IS NULL THEN
      SELECT *
      INTO v_deal
      FROM public.deals d
      WHERE d.organization_id = v_contact.organization_id
        AND d.company_id = v_company_id
        AND d.closed_at IS NULL
      FOR UPDATE;
    END IF;
  END IF;

  IF v_deal.id IS NULL THEN
    RAISE EXCEPTION 'Unable to create or lock an open deal for company %', v_company_id;
  END IF;

  IF public.crm_deal_stage_level(v_deal_stage) > public.crm_deal_stage_level(v_deal.stage) THEN
    PERFORM set_config('app.crm_actor', 'system', TRUE);
    PERFORM set_config('app.crm_actor_user_id', '', TRUE);
    PERFORM set_config('app.crm_contact_id', v_contact.id::TEXT, TRUE);

    UPDATE public.deals
    SET stage = v_deal_stage,
        stage_contact_id = v_contact.id,
        owner_user_id = COALESCE(
          owner_user_id,
          v_contact.assigned_to_user_id,
          v_company_owner_id,
          v_campaign_owner_id
        ),
        source_campaign_id = COALESCE(source_campaign_id, v_source_campaign_id)
    WHERE id = v_deal.id
    RETURNING * INTO v_deal;
  ELSIF v_deal.owner_user_id IS NULL AND COALESCE(
    v_contact.assigned_to_user_id,
    v_company_owner_id,
    v_campaign_owner_id
  ) IS NOT NULL THEN
    PERFORM set_config('app.crm_actor', 'system', TRUE);
    PERFORM set_config('app.crm_actor_user_id', '', TRUE);
    PERFORM set_config('app.crm_contact_id', v_contact.id::TEXT, TRUE);

    UPDATE public.deals
    SET owner_user_id = COALESCE(
          v_contact.assigned_to_user_id,
          v_company_owner_id,
          v_campaign_owner_id
        ),
        source_campaign_id = COALESCE(source_campaign_id, v_source_campaign_id)
    WHERE id = v_deal.id
    RETURNING * INTO v_deal;
  END IF;

  RETURN v_deal.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_crm_deal_from_company_contact()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_contact_stage TEXT;
BEGIN
  SELECT c.pipeline_stage
  INTO v_contact_stage
  FROM public.contacts c
  WHERE c.id = NEW.contact_id
    AND c.organization_id = NEW.organization_id;

  IF v_contact_stage IS NULL THEN
    RETURN NEW;
  END IF;

  BEGIN
    PERFORM public.project_contact_to_crm_deal(NEW.contact_id);
  EXCEPTION WHEN OTHERS THEN
    BEGIN
      INSERT INTO public.crm_deal_projection_failures (
        organization_id,
        contact_id,
        contact_stage,
        error_code,
        error_message
      ) VALUES (
        NEW.organization_id,
        NEW.contact_id,
        v_contact_stage,
        SQLSTATE,
        SQLERRM
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'CRM deal projection and failure logging failed for company contact %: %', NEW.id, SQLERRM;
    END;
  END;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_crm_deal_from_contact_stage()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.pipeline_stage IS NOT DISTINCT FROM OLD.pipeline_stage THEN
    RETURN NEW;
  END IF;

  IF NEW.pipeline_stage IS NULL THEN
    RETURN NEW;
  END IF;

  BEGIN
    PERFORM public.project_contact_to_crm_deal(NEW.id);
  EXCEPTION WHEN OTHERS THEN
    BEGIN
      INSERT INTO public.crm_deal_projection_failures (
        organization_id,
        contact_id,
        contact_stage,
        error_code,
        error_message
      ) VALUES (
        NEW.organization_id,
        NEW.id,
        NEW.pipeline_stage,
        SQLSTATE,
        SQLERRM
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'CRM deal projection and failure logging failed for contact %: %', NEW.id, SQLERRM;
    END;
  END;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_crm_deal_from_contact_stage ON public.contacts;
CREATE TRIGGER trg_sync_crm_deal_from_contact_stage
  AFTER INSERT OR UPDATE OF pipeline_stage ON public.contacts
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_crm_deal_from_contact_stage();

DROP TRIGGER IF EXISTS trg_sync_crm_deal_from_company_contact ON public.company_contacts;
CREATE TRIGGER trg_sync_crm_deal_from_company_contact
  AFTER INSERT ON public.company_contacts
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_crm_deal_from_company_contact();

CREATE OR REPLACE FUNCTION public.reconcile_crm_deals(p_organization_id TEXT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_contact RECORD;
  v_projected INTEGER := 0;
  v_skipped INTEGER := 0;
  v_failed INTEGER := 0;
  v_previous_notification_setting TEXT := current_setting('app.crm_suppress_notifications', TRUE);
  v_floored INTEGER := 0;
BEGIN
  -- Reconciliation/backfill must never fan out historical deal notifications.
  PERFORM set_config('app.crm_suppress_notifications', 'true', TRUE);

  FOR v_contact IN
    SELECT c.id, c.organization_id, c.pipeline_stage
    FROM public.contacts c
    WHERE (p_organization_id IS NULL OR c.organization_id = p_organization_id)
      AND public.map_contact_stage_to_deal_stage(c.pipeline_stage) IN (
        'LEAD',
        'MEETING_REQUESTED',
        'MEETING_BOOKED',
        'PRESENTATION',
        'NEGOTIATION',
        'AGREEMENT'
      )
    ORDER BY c.organization_id, c.stage_updated_at NULLS FIRST, c.created_at, c.id
  LOOP
    BEGIN
      IF public.project_contact_to_crm_deal(v_contact.id) IS NULL THEN
        v_skipped := v_skipped + 1;
      ELSE
        v_projected := v_projected + 1;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      v_failed := v_failed + 1;

      BEGIN
        INSERT INTO public.crm_deal_projection_failures (
          organization_id,
          contact_id,
          contact_stage,
          error_code,
          error_message
        ) VALUES (
          v_contact.organization_id,
          v_contact.id,
          v_contact.pipeline_stage,
          SQLSTATE,
          SQLERRM
        );
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'CRM deal reconciliation failure logging failed for contact %: %', v_contact.id, SQLERRM;
      END;
    END;
  END LOOP;

  -- Backfilled rows get a one-day runway before the 14-day nurture threshold.
  -- Recent real activity remains authoritative because GREATEST never rewinds it.
  UPDATE public.deals d
  SET last_activity_at = GREATEST(d.last_activity_at, NOW() - INTERVAL '13 days')
  WHERE (p_organization_id IS NULL OR d.organization_id = p_organization_id)
    AND d.closed_at IS NULL
    AND d.creation_source = 'automatic';
  GET DIAGNOSTICS v_floored = ROW_COUNT;

  -- Reconciliation order must not decide the account's primary person. Choose
  -- the highest-stage active contact after all forward projections finish.
  WITH ranked_contacts AS (
    SELECT
      d.id AS deal_id,
      c.id AS contact_id,
      ROW_NUMBER() OVER (
        PARTITION BY d.id
        ORDER BY public.crm_deal_stage_level(
          public.map_contact_stage_to_deal_stage(c.pipeline_stage)
        ) DESC,
          GREATEST(c.stage_updated_at, c.last_incoming_email_at) DESC NULLS LAST,
          c.id
      ) AS contact_rank
    FROM public.deals d
    JOIN public.company_contacts cc
      ON cc.organization_id = d.organization_id
     AND cc.company_id = d.company_id
    JOIN public.contacts c
      ON c.id = cc.contact_id
     AND c.organization_id = cc.organization_id
    WHERE (p_organization_id IS NULL OR d.organization_id = p_organization_id)
      AND d.closed_at IS NULL
      AND public.map_contact_stage_to_deal_stage(c.pipeline_stage) IN (
        'LEAD', 'MEETING_REQUESTED', 'MEETING_BOOKED',
        'PRESENTATION', 'NEGOTIATION', 'AGREEMENT'
      )
  )
  UPDATE public.deals d
  SET primary_contact_id = ranked_contacts.contact_id
  FROM ranked_contacts
  WHERE ranked_contacts.deal_id = d.id
    AND ranked_contacts.contact_rank = 1
    AND d.primary_contact_id IS DISTINCT FROM ranked_contacts.contact_id;

  PERFORM set_config(
    'app.crm_suppress_notifications',
    COALESCE(v_previous_notification_setting, 'false'),
    TRUE
  );

  RETURN JSONB_BUILD_OBJECT(
    'projected', v_projected,
    'skipped', v_skipped,
    'failed', v_failed,
    'activity_clock_floored', v_floored
  );
END;
$$;

REVOKE ALL ON FUNCTION public.project_contact_to_crm_deal(UUID) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.reconcile_crm_deals(TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.project_contact_to_crm_deal(UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.reconcile_crm_deals(TEXT) TO service_role;

COMMENT ON TABLE public.crm_deal_projection_failures IS
  'Failure ledger for contact-to-deal projection. Contact writes are never rolled back by deal projection errors.';

COMMENT ON FUNCTION public.map_contact_stage_to_deal_stage(TEXT) IS
  'Maps contact stages to deal stages. CLOSED_WON intentionally returns NULL because deal wins are manual-only.';

COMMENT ON FUNCTION public.reconcile_crm_deals(TEXT) IS
  'Service-role-only idempotent reconciliation for active contact stages. Historical closed contacts are excluded.';

-- Backfill is intentionally explicit. After schema verification, run:
-- SELECT public.reconcile_crm_deals();
--
-- Verify after apply:
-- SELECT public.map_contact_stage_to_deal_stage('CLOSED_WON') IS NULL AS won_is_manual_only;
-- SELECT public.map_contact_stage_to_deal_stage('APPOINTMENT_SCHEDULED') = 'MEETING_BOOKED' AS mapping_ok;
-- SELECT COUNT(*) FROM public.crm_deal_projection_failures WHERE resolved_at IS NULL;
--
-- Rollback:
-- DROP TRIGGER IF EXISTS trg_sync_crm_deal_from_contact_stage ON public.contacts;
-- DROP TRIGGER IF EXISTS trg_sync_crm_deal_from_company_contact ON public.company_contacts;
-- DROP FUNCTION IF EXISTS public.sync_crm_deal_from_contact_stage();
-- DROP FUNCTION IF EXISTS public.sync_crm_deal_from_company_contact();
-- DROP FUNCTION IF EXISTS public.reconcile_crm_deals(TEXT);
-- DROP FUNCTION IF EXISTS public.project_contact_to_crm_deal(UUID);
-- DROP FUNCTION IF EXISTS public.crm_deal_stage_level(TEXT);
-- DROP FUNCTION IF EXISTS public.map_contact_stage_to_deal_stage(TEXT);
-- DROP TABLE IF EXISTS public.crm_deal_projection_failures;
