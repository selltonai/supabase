-- ============================================================
-- Migration: 344_crm-deals-foundation
-- Date:      2026-07-16
-- Purpose:   Add the authoritative CRM deal and activity contracts.
-- Projects:  selltonai-database/supabase (owner), selltonai (writer/reader),
--            selltonai-modal and backoffice (future consumers).
-- Contract:  Additive. Existing contacts, tasks, notifications, Gmail,
--            LinkedIn, and Sellton Brain contracts are unchanged.
-- Idempotency: Re-runnable via IF NOT EXISTS and CREATE OR REPLACE.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.deals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id TEXT NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  company_id UUID NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  primary_contact_id UUID REFERENCES public.contacts(id) ON DELETE SET NULL,
  stage_contact_id UUID REFERENCES public.contacts(id) ON DELETE SET NULL,
  source_campaign_id UUID REFERENCES public.campaigns(id) ON DELETE SET NULL,
  owner_user_id TEXT REFERENCES public."user"(id) ON DELETE SET NULL,
  name TEXT NOT NULL,
  stage TEXT NOT NULL DEFAULT 'LEAD',
  amount NUMERIC(14, 2),
  currency TEXT NOT NULL DEFAULT 'USD',
  creation_source TEXT NOT NULL DEFAULT 'automatic',
  nurture_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  stage_updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_activity_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  closed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT deals_name_not_blank CHECK (BTRIM(name) <> ''),
  CONSTRAINT deals_stage_check CHECK (
    stage IN (
      'LEAD',
      'MEETING_REQUESTED',
      'MEETING_BOOKED',
      'PRESENTATION',
      'NEGOTIATION',
      'AGREEMENT',
      'WON',
      'LOST'
    )
  ),
  CONSTRAINT deals_amount_nonnegative CHECK (amount IS NULL OR amount >= 0),
  CONSTRAINT deals_currency_check CHECK (currency IN ('USD', 'EUR', 'GBP')),
  CONSTRAINT deals_creation_source_check CHECK (creation_source IN ('automatic', 'manual')),
  CONSTRAINT deals_closed_state_check CHECK (
    (stage IN ('WON', 'LOST') AND closed_at IS NOT NULL)
    OR (stage NOT IN ('WON', 'LOST') AND closed_at IS NULL)
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_deals_one_open_per_company
  ON public.deals (organization_id, company_id)
  WHERE closed_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_deals_org_stage_updated
  ON public.deals (organization_id, stage, stage_updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_deals_org_owner_stage
  ON public.deals (organization_id, owner_user_id, stage, stage_updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_deals_org_last_activity_open
  ON public.deals (organization_id, last_activity_at)
  WHERE closed_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_deals_primary_contact
  ON public.deals (primary_contact_id)
  WHERE primary_contact_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_deals_source_campaign
  ON public.deals (source_campaign_id)
  WHERE source_campaign_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.deal_activities (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  deal_id UUID NOT NULL REFERENCES public.deals(id) ON DELETE CASCADE,
  organization_id TEXT NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  activity_type TEXT NOT NULL,
  actor TEXT NOT NULL DEFAULT 'system',
  actor_user_id TEXT REFERENCES public."user"(id) ON DELETE SET NULL,
  contact_id UUID REFERENCES public.contacts(id) ON DELETE SET NULL,
  title TEXT NOT NULL,
  metadata JSONB NOT NULL DEFAULT '{}'::JSONB,
  bumps_last_activity BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT deal_activities_title_not_blank CHECK (BTRIM(title) <> ''),
  CONSTRAINT deal_activities_type_check CHECK (
    activity_type IN (
      'deal_created',
      'stage_change',
      'amount_change',
      'owner_change',
      'nurture_change',
      'note',
      'email_in',
      'email_out',
      'linkedin_in',
      'linkedin_out',
      'task_completed'
    )
  ),
  CONSTRAINT deal_activities_actor_check CHECK (actor IN ('system', 'user')),
  CONSTRAINT deal_activities_metadata_object_check CHECK (JSONB_TYPEOF(metadata) = 'object')
);

CREATE INDEX IF NOT EXISTS idx_deal_activities_deal_created
  ON public.deal_activities (deal_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_deal_activities_org_created
  ON public.deal_activities (organization_id, created_at DESC);

ALTER TABLE public.organization_settings
  ADD COLUMN IF NOT EXISTS default_deal_amount NUMERIC(14, 2),
  ADD COLUMN IF NOT EXISTS default_deal_currency TEXT NOT NULL DEFAULT 'USD';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.organization_settings'::REGCLASS
      AND conname = 'organization_settings_default_deal_amount_nonnegative'
  ) THEN
    ALTER TABLE public.organization_settings
      ADD CONSTRAINT organization_settings_default_deal_amount_nonnegative
      CHECK (default_deal_amount IS NULL OR default_deal_amount >= 0);
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.organization_settings'::REGCLASS
      AND conname = 'organization_settings_default_deal_currency_check'
  ) THEN
    ALTER TABLE public.organization_settings
      ADD CONSTRAINT organization_settings_default_deal_currency_check
      CHECK (default_deal_currency IN ('USD', 'EUR', 'GBP'));
  END IF;
END
$$;

CREATE OR REPLACE FUNCTION public.prepare_crm_deal_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.stage IS DISTINCT FROM OLD.stage THEN
    NEW.stage_updated_at := NOW();

    IF NEW.stage IN ('WON', 'LOST') THEN
      NEW.closed_at := NOW();
    ELSE
      NEW.closed_at := NULL;
    END IF;
  END IF;

  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prepare_crm_deal_update ON public.deals;
CREATE TRIGGER trg_prepare_crm_deal_update
  BEFORE UPDATE ON public.deals
  FOR EACH ROW
  EXECUTE FUNCTION public.prepare_crm_deal_update();

CREATE OR REPLACE FUNCTION public.validate_crm_deal_activity_scope()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.deals d
    WHERE d.id = NEW.deal_id
      AND d.organization_id = NEW.organization_id
  ) THEN
    RAISE EXCEPTION 'Deal % does not belong to organization %', NEW.deal_id, NEW.organization_id
      USING ERRCODE = '23514';
  END IF;

  IF NEW.contact_id IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM public.deals d
    JOIN public.company_contacts cc
      ON cc.company_id = d.company_id
     AND cc.organization_id = d.organization_id
    WHERE d.id = NEW.deal_id
      AND d.organization_id = NEW.organization_id
      AND cc.contact_id = NEW.contact_id
  ) THEN
    RAISE EXCEPTION 'Contact % is not linked to the deal company', NEW.contact_id
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_crm_deal_activity_scope ON public.deal_activities;
CREATE TRIGGER trg_validate_crm_deal_activity_scope
  BEFORE INSERT OR UPDATE ON public.deal_activities
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_crm_deal_activity_scope();

CREATE OR REPLACE FUNCTION public.bump_crm_deal_last_activity()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.bumps_last_activity THEN
    UPDATE public.deals
    SET last_activity_at = GREATEST(last_activity_at, NEW.created_at)
    WHERE id = NEW.deal_id
      AND organization_id = NEW.organization_id;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_bump_crm_deal_last_activity ON public.deal_activities;
CREATE TRIGGER trg_bump_crm_deal_last_activity
  AFTER INSERT ON public.deal_activities
  FOR EACH ROW
  EXECUTE FUNCTION public.bump_crm_deal_last_activity();

CREATE OR REPLACE FUNCTION public.audit_crm_deal_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_actor TEXT := COALESCE(NULLIF(current_setting('app.crm_actor', TRUE), ''), 'system');
  v_actor_user_id TEXT := NULLIF(current_setting('app.crm_actor_user_id', TRUE), '');
  v_contact_id UUID := NULLIF(current_setting('app.crm_contact_id', TRUE), '')::UUID;
BEGIN
  IF v_actor NOT IN ('system', 'user') THEN
    v_actor := 'system';
    v_actor_user_id := NULL;
  END IF;

  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.deal_activities (
      deal_id,
      organization_id,
      activity_type,
      actor,
      actor_user_id,
      contact_id,
      title,
      metadata,
      bumps_last_activity,
      created_at
    ) VALUES (
      NEW.id,
      NEW.organization_id,
      'deal_created',
      v_actor,
      v_actor_user_id,
      COALESCE(v_contact_id, NEW.primary_contact_id),
      'Deal created',
      JSONB_BUILD_OBJECT('stage', NEW.stage, 'creation_source', NEW.creation_source),
      FALSE,
      NEW.created_at
    );

    RETURN NEW;
  END IF;

  IF NEW.stage IS DISTINCT FROM OLD.stage THEN
    INSERT INTO public.deal_activities (
      deal_id, organization_id, activity_type, actor, actor_user_id, contact_id,
      title, metadata, bumps_last_activity
    ) VALUES (
      NEW.id, NEW.organization_id, 'stage_change', v_actor, v_actor_user_id,
      CASE
        WHEN v_actor = 'user' THEN v_contact_id
        ELSE COALESCE(v_contact_id, NEW.stage_contact_id)
      END,
      'Deal stage changed',
      JSONB_BUILD_OBJECT('from', OLD.stage, 'to', NEW.stage), TRUE
    );
  END IF;

  IF NEW.amount IS DISTINCT FROM OLD.amount OR NEW.currency IS DISTINCT FROM OLD.currency THEN
    INSERT INTO public.deal_activities (
      deal_id, organization_id, activity_type, actor, actor_user_id, contact_id,
      title, metadata, bumps_last_activity
    ) VALUES (
      NEW.id, NEW.organization_id, 'amount_change', v_actor, v_actor_user_id,
      v_contact_id, 'Deal value changed',
      JSONB_BUILD_OBJECT(
        'from_amount', OLD.amount,
        'to_amount', NEW.amount,
        'from_currency', OLD.currency,
        'to_currency', NEW.currency
      ), FALSE
    );
  END IF;

  IF NEW.owner_user_id IS DISTINCT FROM OLD.owner_user_id THEN
    INSERT INTO public.deal_activities (
      deal_id, organization_id, activity_type, actor, actor_user_id, contact_id,
      title, metadata, bumps_last_activity
    ) VALUES (
      NEW.id, NEW.organization_id, 'owner_change', v_actor, v_actor_user_id,
      v_contact_id, 'Deal owner changed',
      JSONB_BUILD_OBJECT('from', OLD.owner_user_id, 'to', NEW.owner_user_id), FALSE
    );
  END IF;

  IF NEW.nurture_enabled IS DISTINCT FROM OLD.nurture_enabled THEN
    INSERT INTO public.deal_activities (
      deal_id, organization_id, activity_type, actor, actor_user_id, contact_id,
      title, metadata, bumps_last_activity
    ) VALUES (
      NEW.id, NEW.organization_id, 'nurture_change', v_actor, v_actor_user_id,
      v_contact_id, 'Deal nurture setting changed',
      JSONB_BUILD_OBJECT('enabled', NEW.nurture_enabled), FALSE
    );
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_audit_crm_deal_change ON public.deals;
CREATE TRIGGER trg_audit_crm_deal_change
  AFTER INSERT OR UPDATE ON public.deals
  FOR EACH ROW
  EXECUTE FUNCTION public.audit_crm_deal_change();

CREATE OR REPLACE FUNCTION public.update_crm_deal(
  p_deal_id UUID,
  p_organization_id TEXT,
  p_actor_user_id TEXT,
  p_changes JSONB
)
RETURNS public.deals
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_deal public.deals;
  v_primary_contact_id UUID;
BEGIN
  IF p_changes IS NULL OR JSONB_TYPEOF(p_changes) <> 'object' OR p_changes = '{}'::JSONB THEN
    RAISE EXCEPTION 'Deal changes must be a non-empty JSON object'
      USING ERRCODE = '22023';
  END IF;

  IF p_changes - ARRAY[
    'name',
    'stage',
    'amount',
    'currency',
    'owner_user_id',
    'primary_contact_id',
    'nurture_enabled'
  ] <> '{}'::JSONB THEN
    RAISE EXCEPTION 'Deal changes contain unsupported fields'
      USING ERRCODE = '22023';
  END IF;

  SELECT *
  INTO v_deal
  FROM public.deals
  WHERE id = p_deal_id
    AND organization_id = p_organization_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Deal not found'
      USING ERRCODE = 'P0002';
  END IF;

  IF p_changes ? 'name' AND NULLIF(BTRIM(p_changes->>'name'), '') IS NULL THEN
    RAISE EXCEPTION 'Deal name cannot be empty'
      USING ERRCODE = '22023';
  END IF;

  IF p_changes ? 'stage' AND COALESCE(p_changes->>'stage', '') NOT IN (
    'LEAD',
    'MEETING_REQUESTED',
    'MEETING_BOOKED',
    'PRESENTATION',
    'NEGOTIATION',
    'AGREEMENT',
    'WON',
    'LOST'
  ) THEN
    RAISE EXCEPTION 'Unsupported deal stage'
      USING ERRCODE = '22023';
  END IF;

  IF p_changes ? 'currency' AND COALESCE(p_changes->>'currency', '') NOT IN ('USD', 'EUR', 'GBP') THEN
    RAISE EXCEPTION 'Unsupported deal currency'
      USING ERRCODE = '22023';
  END IF;

  IF p_changes ? 'amount'
    AND p_changes->'amount' <> 'null'::JSONB
    AND (p_changes->>'amount')::NUMERIC < 0 THEN
    RAISE EXCEPTION 'Deal amount cannot be negative'
      USING ERRCODE = '22023';
  END IF;

  IF p_changes ? 'primary_contact_id' AND p_changes->'primary_contact_id' <> 'null'::JSONB THEN
    v_primary_contact_id := (p_changes->>'primary_contact_id')::UUID;

    IF NOT EXISTS (
      SELECT 1
      FROM public.company_contacts cc
      WHERE cc.contact_id = v_primary_contact_id
        AND cc.company_id = v_deal.company_id
        AND cc.organization_id = p_organization_id
    ) THEN
      RAISE EXCEPTION 'Primary contact is not linked to the deal company'
        USING ERRCODE = '23514';
    END IF;
  END IF;

  IF p_changes ? 'owner_user_id'
    AND p_changes->'owner_user_id' <> 'null'::JSONB
    AND NULLIF(p_changes->>'owner_user_id', '') IS NOT NULL
    AND NOT EXISTS (
      SELECT 1
      FROM public.user_organizations uo
      WHERE uo.organization_id = p_organization_id
        AND uo.user_id = p_changes->>'owner_user_id'
    ) THEN
    RAISE EXCEPTION 'Deal owner is not an organization member'
      USING ERRCODE = '23514';
  END IF;

  IF p_actor_user_id IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM public.user_organizations uo
    WHERE uo.organization_id = p_organization_id
      AND uo.user_id = p_actor_user_id
  ) THEN
    RAISE EXCEPTION 'Deal actor is not an organization member'
      USING ERRCODE = '23514';
  END IF;

  PERFORM set_config('app.crm_actor', 'user', TRUE);
  PERFORM set_config('app.crm_actor_user_id', COALESCE(p_actor_user_id, ''), TRUE);
  PERFORM set_config('app.crm_contact_id', '', TRUE);

  UPDATE public.deals
  SET name = CASE
        WHEN p_changes ? 'name' THEN BTRIM(p_changes->>'name')
        ELSE name
      END,
      stage = CASE
        WHEN p_changes ? 'stage' THEN p_changes->>'stage'
        ELSE stage
      END,
      amount = CASE
        WHEN p_changes ? 'amount' THEN (p_changes->>'amount')::NUMERIC
        ELSE amount
      END,
      currency = CASE
        WHEN p_changes ? 'currency' THEN p_changes->>'currency'
        ELSE currency
      END,
      owner_user_id = CASE
        WHEN p_changes ? 'owner_user_id' THEN NULLIF(p_changes->>'owner_user_id', '')
        ELSE owner_user_id
      END,
      primary_contact_id = CASE
        WHEN p_changes ? 'primary_contact_id' THEN (p_changes->>'primary_contact_id')::UUID
        ELSE primary_contact_id
      END,
      nurture_enabled = CASE
        WHEN p_changes ? 'nurture_enabled' THEN (p_changes->>'nurture_enabled')::BOOLEAN
        ELSE nurture_enabled
      END
  WHERE id = p_deal_id
    AND organization_id = p_organization_id
  RETURNING * INTO v_deal;

  RETURN v_deal;
END;
$$;

ALTER TABLE public.deals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.deal_activities ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.deals FROM anon, authenticated;
REVOKE ALL ON TABLE public.deal_activities FROM anon, authenticated;
REVOKE ALL ON FUNCTION public.update_crm_deal(UUID, TEXT, TEXT, JSONB) FROM PUBLIC, anon, authenticated;

GRANT ALL ON TABLE public.deals TO service_role;
GRANT ALL ON TABLE public.deal_activities TO service_role;
GRANT EXECUTE ON FUNCTION public.update_crm_deal(UUID, TEXT, TEXT, JSONB) TO service_role;

COMMENT ON TABLE public.deals IS
  'Authoritative company-scoped CRM opportunities. Contact stages may advance deals but manual deal changes never write back to contacts.';

COMMENT ON TABLE public.deal_activities IS
  'Auditable deal events. Only rows with bumps_last_activity=true advance the nurture activity clock.';

COMMENT ON COLUMN public.deals.source_campaign_id IS
  'Nullable deterministic attribution. Never populated from an arbitrary latest campaign.';

COMMENT ON COLUMN public.deals.stage_contact_id IS
  'Contact whose event most recently caused an automatic deal-stage change.';

COMMENT ON FUNCTION public.update_crm_deal(UUID, TEXT, TEXT, JSONB) IS
  'Service-role-only atomic deal mutation. The audit trigger records changed business fields.';

-- Verify after apply:
-- SELECT relname, relrowsecurity FROM pg_class WHERE relname IN ('deals', 'deal_activities');
-- SELECT indexname FROM pg_indexes WHERE tablename = 'deals' ORDER BY indexname;
-- SELECT column_name FROM information_schema.columns
--   WHERE table_name = 'organization_settings' AND column_name LIKE 'default_deal_%';
--
-- Rollback (application code must be rolled back first):
-- DROP FUNCTION IF EXISTS public.update_crm_deal(UUID, TEXT, TEXT, JSONB);
-- DROP TABLE IF EXISTS public.deal_activities CASCADE;
-- DROP TABLE IF EXISTS public.deals CASCADE;
-- ALTER TABLE public.organization_settings
--   DROP COLUMN IF EXISTS default_deal_amount,
--   DROP COLUMN IF EXISTS default_deal_currency;
