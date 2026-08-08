-- ============================================================
-- Migration: CRM deals reconciliation rollout gate
-- Date:      2026-08-08
-- Purpose:   Require verified contact-to-deal reconciliation before CRM flags.
-- Projects:  selltonai-database/supabase (owner), selltonai and
--            selltonai-modal (organization_settings consumers).
-- Contract:  Additive. No flag is enabled by this migration. Reconciliation
--            remains silent and service-role-only.
-- Depends:   CRM deals contact projection and CRM automation flag migrations.
-- ============================================================

CREATE OR REPLACE FUNCTION public.crm_deal_reconciliation_readiness(p_organization_id TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_settings_present BOOLEAN;
  v_eligible_contacts INTEGER := 0;
  v_eligible_companies INTEGER := 0;
  v_existing_open_deals INTEGER := 0;
  v_missing_deals INTEGER := 0;
  v_lagging_stages INTEGER := 0;
  v_primary_contact_mismatches INTEGER := 0;
  v_duplicate_open_deals INTEGER := 0;
  v_unresolved_failures INTEGER := 0;
  v_ready BOOLEAN;
BEGIN
  IF NULLIF(BTRIM(p_organization_id), '') IS NULL THEN
    RAISE EXCEPTION 'organization_id is required'
      USING ERRCODE = '22023';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.organization o
    WHERE o.id = p_organization_id
  ) THEN
    RAISE EXCEPTION 'Organization not found'
      USING ERRCODE = 'P0002';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.organization_settings os
    WHERE os.organization_id = p_organization_id
  )
  INTO v_settings_present;

  WITH active_contact_rows AS (
    SELECT
      c.id AS contact_id,
      cc.company_id,
      public.map_contact_stage_to_deal_stage(c.pipeline_stage) AS expected_stage,
      public.crm_deal_stage_level(
        public.map_contact_stage_to_deal_stage(c.pipeline_stage)
      ) AS expected_stage_level,
      ROW_NUMBER() OVER (
        PARTITION BY cc.company_id
        ORDER BY public.crm_deal_stage_level(
          public.map_contact_stage_to_deal_stage(c.pipeline_stage)
        ) DESC,
          GREATEST(c.stage_updated_at, c.last_incoming_email_at) DESC NULLS LAST,
          c.id
      ) AS contact_rank
    FROM public.contacts c
    JOIN public.company_contacts cc
      ON cc.contact_id = c.id
     AND cc.organization_id = c.organization_id
    WHERE c.organization_id = p_organization_id
      AND public.map_contact_stage_to_deal_stage(c.pipeline_stage) IN (
        'LEAD',
        'MEETING_REQUESTED',
        'MEETING_BOOKED',
        'PRESENTATION',
        'NEGOTIATION',
        'AGREEMENT'
      )
  ),
  expected_companies AS (
    SELECT company_id, MAX(expected_stage_level) AS expected_stage_level
    FROM active_contact_rows
    GROUP BY company_id
  )
  SELECT
    (SELECT COUNT(*) FROM active_contact_rows),
    (SELECT COUNT(*) FROM expected_companies),
    (
      SELECT COUNT(*)
      FROM expected_companies expected
      LEFT JOIN public.deals d
        ON d.organization_id = p_organization_id
       AND d.company_id = expected.company_id
       AND d.closed_at IS NULL
      WHERE d.id IS NULL
    ),
    (
      SELECT COUNT(*)
      FROM expected_companies expected
      JOIN public.deals d
        ON d.organization_id = p_organization_id
       AND d.company_id = expected.company_id
       AND d.closed_at IS NULL
      WHERE public.crm_deal_stage_level(d.stage) < expected.expected_stage_level
    ),
    (
      SELECT COUNT(*)
      FROM active_contact_rows ranked
      JOIN public.deals d
        ON d.organization_id = p_organization_id
       AND d.company_id = ranked.company_id
       AND d.closed_at IS NULL
      WHERE ranked.contact_rank = 1
        AND d.primary_contact_id IS DISTINCT FROM ranked.contact_id
    )
  INTO
    v_eligible_contacts,
    v_eligible_companies,
    v_missing_deals,
    v_lagging_stages,
    v_primary_contact_mismatches;

  SELECT COUNT(*)
  INTO v_existing_open_deals
  FROM public.deals d
  WHERE d.organization_id = p_organization_id
    AND d.closed_at IS NULL;

  SELECT COUNT(*)
  INTO v_duplicate_open_deals
  FROM (
    SELECT d.company_id
    FROM public.deals d
    WHERE d.organization_id = p_organization_id
      AND d.closed_at IS NULL
    GROUP BY d.company_id
    HAVING COUNT(*) > 1
  ) duplicates;

  SELECT COUNT(*)
  INTO v_unresolved_failures
  FROM public.crm_deal_projection_failures failure
  WHERE failure.organization_id = p_organization_id
    AND failure.resolved_at IS NULL;

  v_ready := (
    v_missing_deals = 0
    AND v_lagging_stages = 0
    AND v_primary_contact_mismatches = 0
    AND v_duplicate_open_deals = 0
    AND v_unresolved_failures = 0
  );

  RETURN JSONB_BUILD_OBJECT(
    'organization_id', p_organization_id,
    'ready_for_flag_enablement', v_ready,
    'organization_settings_present', v_settings_present,
    'eligible_contact_count', v_eligible_contacts,
    'eligible_company_count', v_eligible_companies,
    'existing_open_deal_count', v_existing_open_deals,
    'missing_deal_count', v_missing_deals,
    'lagging_stage_count', v_lagging_stages,
    'primary_contact_mismatch_count', v_primary_contact_mismatches,
    'duplicate_open_deal_count', v_duplicate_open_deals,
    'unresolved_projection_failure_count', v_unresolved_failures
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.reconcile_crm_deals_for_rollout(
  p_organization_id TEXT,
  p_apply BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_pipeline_enabled BOOLEAN;
  v_automation_enabled BOOLEAN;
  v_before JSONB;
  v_reconciliation JSONB := NULL;
  v_after JSONB;
  v_resolved_failures INTEGER := 0;
BEGIN
  IF NULLIF(BTRIM(p_organization_id), '') IS NULL THEN
    RAISE EXCEPTION 'organization_id is required'
      USING ERRCODE = '22023';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('crm-deal-rollout:' || p_organization_id));

  SELECT os.crm_pipeline_enabled, os.crm_automation_enabled
  INTO v_pipeline_enabled, v_automation_enabled
  FROM public.organization_settings os
  WHERE os.organization_id = p_organization_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Organization settings not found'
      USING ERRCODE = 'P0002';
  END IF;

  v_before := public.crm_deal_reconciliation_readiness(p_organization_id);

  IF NOT p_apply THEN
    RETURN JSONB_BUILD_OBJECT(
      'mode', 'dry-run',
      'organization_id', p_organization_id,
      'flags_enabled', v_pipeline_enabled OR v_automation_enabled,
      'before', v_before,
      'apply_required', NOT COALESCE((v_before->>'ready_for_flag_enablement')::BOOLEAN, FALSE)
    );
  END IF;

  IF v_pipeline_enabled OR v_automation_enabled THEN
    RAISE EXCEPTION 'Disable CRM pipeline and automation flags before reconciliation'
      USING ERRCODE = '23514';
  END IF;

  v_reconciliation := public.reconcile_crm_deals(p_organization_id);

  -- Old failure rows are resolved only when the source contact no longer needs
  -- an active deal or its current company deal now satisfies the projection.
  UPDATE public.crm_deal_projection_failures failure
  SET resolved_at = NOW()
  FROM public.contacts c
  WHERE failure.organization_id = p_organization_id
    AND failure.resolved_at IS NULL
    AND failure.contact_id = c.id
    AND c.organization_id = failure.organization_id
    AND (
      public.map_contact_stage_to_deal_stage(c.pipeline_stage) NOT IN (
        'LEAD',
        'MEETING_REQUESTED',
        'MEETING_BOOKED',
        'PRESENTATION',
        'NEGOTIATION',
        'AGREEMENT'
      )
      OR EXISTS (
        SELECT 1
        FROM public.company_contacts cc
        JOIN public.deals d
          ON d.organization_id = cc.organization_id
         AND d.company_id = cc.company_id
         AND d.closed_at IS NULL
        WHERE cc.organization_id = c.organization_id
          AND cc.contact_id = c.id
          AND public.crm_deal_stage_level(d.stage) >= public.crm_deal_stage_level(
            public.map_contact_stage_to_deal_stage(c.pipeline_stage)
          )
      )
    );
  GET DIAGNOSTICS v_resolved_failures = ROW_COUNT;

  v_after := public.crm_deal_reconciliation_readiness(p_organization_id);

  RETURN JSONB_BUILD_OBJECT(
    'mode', 'apply',
    'organization_id', p_organization_id,
    'before', v_before,
    'reconciliation', v_reconciliation,
    'resolved_failure_rows', v_resolved_failures,
    'after', v_after,
    'ready_for_flag_enablement',
      COALESCE((v_after->>'ready_for_flag_enablement')::BOOLEAN, FALSE)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.enable_crm_pipeline_after_reconciliation(
  p_organization_id TEXT,
  p_enable_automation BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_readiness JSONB;
  v_settings public.organization_settings;
BEGIN
  IF NULLIF(BTRIM(p_organization_id), '') IS NULL THEN
    RAISE EXCEPTION 'organization_id is required'
      USING ERRCODE = '22023';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('crm-deal-rollout:' || p_organization_id));
  v_readiness := public.crm_deal_reconciliation_readiness(p_organization_id);

  IF NOT COALESCE((v_readiness->>'ready_for_flag_enablement')::BOOLEAN, FALSE) THEN
    RAISE EXCEPTION 'CRM deal reconciliation is not ready for flag enablement'
      USING ERRCODE = '23514', DETAIL = v_readiness::TEXT;
  END IF;

  UPDATE public.organization_settings
  SET crm_pipeline_enabled = TRUE,
      crm_automation_enabled = p_enable_automation
  WHERE organization_id = p_organization_id
  RETURNING * INTO v_settings;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Organization settings not found'
      USING ERRCODE = 'P0002';
  END IF;

  RETURN JSONB_BUILD_OBJECT(
    'organization_id', p_organization_id,
    'crm_pipeline_enabled', v_settings.crm_pipeline_enabled,
    'crm_automation_enabled', v_settings.crm_automation_enabled,
    'verified_at', NOW(),
    'readiness', v_readiness
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.guard_crm_pipeline_flag_enablement()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_enabling_pipeline BOOLEAN;
  v_enabling_automation BOOLEAN;
  v_readiness JSONB;
BEGIN
  IF NEW.crm_automation_enabled AND NOT NEW.crm_pipeline_enabled THEN
    RAISE EXCEPTION 'CRM automation requires the CRM pipeline flag'
      USING ERRCODE = '23514';
  END IF;

  v_enabling_pipeline := NEW.crm_pipeline_enabled AND (
    TG_OP = 'INSERT' OR NOT COALESCE(OLD.crm_pipeline_enabled, FALSE)
  );
  v_enabling_automation := NEW.crm_automation_enabled AND (
    TG_OP = 'INSERT' OR NOT COALESCE(OLD.crm_automation_enabled, FALSE)
  );

  IF v_enabling_pipeline OR v_enabling_automation THEN
    PERFORM pg_advisory_xact_lock(hashtext('crm-deal-rollout:' || NEW.organization_id));
    v_readiness := public.crm_deal_reconciliation_readiness(NEW.organization_id);

    IF NOT COALESCE((v_readiness->>'ready_for_flag_enablement')::BOOLEAN, FALSE) THEN
      RAISE EXCEPTION 'Reconcile CRM deals before enabling pipeline flags'
        USING ERRCODE = '23514', DETAIL = v_readiness::TEXT;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_crm_pipeline_flag_insert ON public.organization_settings;
CREATE TRIGGER trg_guard_crm_pipeline_flag_insert
  BEFORE INSERT ON public.organization_settings
  FOR EACH ROW
  EXECUTE FUNCTION public.guard_crm_pipeline_flag_enablement();

DROP TRIGGER IF EXISTS trg_guard_crm_pipeline_flag_update ON public.organization_settings;
CREATE TRIGGER trg_guard_crm_pipeline_flag_update
  BEFORE UPDATE OF crm_pipeline_enabled, crm_automation_enabled ON public.organization_settings
  FOR EACH ROW
  EXECUTE FUNCTION public.guard_crm_pipeline_flag_enablement();

REVOKE ALL ON FUNCTION public.crm_deal_reconciliation_readiness(TEXT)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.reconcile_crm_deals_for_rollout(TEXT, BOOLEAN)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.enable_crm_pipeline_after_reconciliation(TEXT, BOOLEAN)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.guard_crm_pipeline_flag_enablement()
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.crm_deal_reconciliation_readiness(TEXT)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.reconcile_crm_deals_for_rollout(TEXT, BOOLEAN)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.enable_crm_pipeline_after_reconciliation(TEXT, BOOLEAN)
  TO service_role;

COMMENT ON FUNCTION public.crm_deal_reconciliation_readiness(TEXT) IS
  'Read-only organization-scoped deal projection readiness report. Service role only.';
COMMENT ON FUNCTION public.reconcile_crm_deals_for_rollout(TEXT, BOOLEAN) IS
  'Dry-run by default; apply reconciles one organization silently and returns post-write readiness.';
COMMENT ON FUNCTION public.enable_crm_pipeline_after_reconciliation(TEXT, BOOLEAN) IS
  'Enables CRM pipeline flags only after a current reconciliation readiness check passes.';
COMMENT ON FUNCTION public.guard_crm_pipeline_flag_enablement() IS
  'Blocks direct CRM flag activation while projected deals are missing, lagging, conflicting, or failed.';

-- Operator sequence (service role):
-- SELECT public.reconcile_crm_deals_for_rollout('<organization-id>', FALSE);
-- SELECT public.reconcile_crm_deals_for_rollout('<organization-id>', TRUE);
-- SELECT public.enable_crm_pipeline_after_reconciliation('<organization-id>', FALSE);
--
-- Rollback:
-- DROP TRIGGER IF EXISTS trg_guard_crm_pipeline_flag_insert ON public.organization_settings;
-- DROP TRIGGER IF EXISTS trg_guard_crm_pipeline_flag_update ON public.organization_settings;
-- DROP FUNCTION IF EXISTS public.guard_crm_pipeline_flag_enablement();
-- DROP FUNCTION IF EXISTS public.enable_crm_pipeline_after_reconciliation(TEXT, BOOLEAN);
-- DROP FUNCTION IF EXISTS public.reconcile_crm_deals_for_rollout(TEXT, BOOLEAN);
-- DROP FUNCTION IF EXISTS public.crm_deal_reconciliation_readiness(TEXT);
