\set ON_ERROR_STOP on

-- Run against a disposable database with the base schema loaded.
-- All fixtures and flag changes roll back.
BEGIN;

\ir ../migrations/release-next/344_crm-deals-foundation.sql
\ir ../migrations/release-next/345_crm-deals-contact-projection.sql
\ir ../migrations/release-next/350_crm-pipeline-v2-snooze-controls.sql
\ir ../migrations/release-next/355_crm-deals-reconciliation-rollout-gate.sql

INSERT INTO public.organization (id, name)
VALUES ('org_crm_rollout_validation', 'CRM Rollout Validation');

INSERT INTO public.organization_settings (
  organization_id,
  default_deal_amount,
  default_deal_currency,
  crm_pipeline_enabled,
  crm_automation_enabled
) VALUES (
  'org_crm_rollout_validation',
  10000,
  'EUR',
  FALSE,
  FALSE
);

INSERT INTO public.companies (id, organization_id, name)
VALUES ('12000000-0000-0000-0000-000000000001', 'org_crm_rollout_validation', 'Rollout Company');

INSERT INTO public.contacts (id, organization_id, name, pipeline_stage, stage_updated_at)
VALUES (
  '22000000-0000-0000-0000-000000000001',
  'org_crm_rollout_validation',
  'Rollout Contact',
  'APPOINTMENT_SCHEDULED',
  NOW()
);

INSERT INTO public.company_contacts (organization_id, company_id, contact_id)
VALUES (
  'org_crm_rollout_validation',
  '12000000-0000-0000-0000-000000000001',
  '22000000-0000-0000-0000-000000000001'
);

-- Simulate a production gap created before the projection trigger existed.
DELETE FROM public.deals
WHERE organization_id = 'org_crm_rollout_validation';

DO $$
DECLARE
  v_readiness JSONB;
  v_dry_run JSONB;
BEGIN
  v_readiness := public.crm_deal_reconciliation_readiness('org_crm_rollout_validation');
  IF (v_readiness->>'ready_for_flag_enablement')::BOOLEAN
    OR (v_readiness->>'missing_deal_count')::INTEGER <> 1 THEN
    RAISE EXCEPTION 'Missing deal was not detected: %', v_readiness;
  END IF;

  v_dry_run := public.reconcile_crm_deals_for_rollout('org_crm_rollout_validation', FALSE);
  IF v_dry_run->>'mode' <> 'dry-run'
    OR NOT (v_dry_run->>'apply_required')::BOOLEAN
    OR EXISTS (
      SELECT 1 FROM public.deals WHERE organization_id = 'org_crm_rollout_validation'
    ) THEN
    RAISE EXCEPTION 'Dry-run wrote data or omitted the repair requirement: %', v_dry_run;
  END IF;
END
$$;

DO $$
BEGIN
  BEGIN
    UPDATE public.organization_settings
    SET crm_pipeline_enabled = TRUE
    WHERE organization_id = 'org_crm_rollout_validation';
    RAISE EXCEPTION 'Pipeline flag unexpectedly enabled before reconciliation';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;
END
$$;

DO $$
DECLARE
  v_apply JSONB;
  v_enable JSONB;
BEGIN
  v_apply := public.reconcile_crm_deals_for_rollout('org_crm_rollout_validation', TRUE);
  IF NOT (v_apply->>'ready_for_flag_enablement')::BOOLEAN
    OR (v_apply#>>'{after,missing_deal_count}')::INTEGER <> 0
    OR (v_apply#>>'{after,lagging_stage_count}')::INTEGER <> 0 THEN
    RAISE EXCEPTION 'Applied reconciliation did not reach readiness: %', v_apply;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.deals
    WHERE organization_id = 'org_crm_rollout_validation'
      AND company_id = '12000000-0000-0000-0000-000000000001'
      AND stage = 'MEETING_BOOKED'
      AND closed_at IS NULL
  ) THEN
    RAISE EXCEPTION 'Reconciliation did not recreate the projected deal';
  END IF;

  v_enable := public.enable_crm_pipeline_after_reconciliation('org_crm_rollout_validation', FALSE);
  IF NOT (v_enable->>'crm_pipeline_enabled')::BOOLEAN
    OR (v_enable->>'crm_automation_enabled')::BOOLEAN THEN
    RAISE EXCEPTION 'Verified flag activation returned the wrong state: %', v_enable;
  END IF;
END
$$;

UPDATE public.organization_settings
SET crm_pipeline_enabled = FALSE,
    crm_automation_enabled = FALSE
WHERE organization_id = 'org_crm_rollout_validation';

INSERT INTO public.crm_deal_projection_failures (
  organization_id,
  contact_id,
  contact_stage,
  error_code,
  error_message
) VALUES (
  'org_crm_rollout_validation',
  NULL,
  'LEAD',
  'XX000',
  'Unresolved rollout test failure'
);

DO $$
BEGIN
  BEGIN
    PERFORM public.enable_crm_pipeline_after_reconciliation('org_crm_rollout_validation', FALSE);
    RAISE EXCEPTION 'Unresolved projection failure did not block flag activation';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;

  BEGIN
    UPDATE public.organization_settings
    SET crm_automation_enabled = TRUE
    WHERE organization_id = 'org_crm_rollout_validation';
    RAISE EXCEPTION 'Automation unexpectedly enabled without pipeline';
  EXCEPTION
    WHEN check_violation THEN NULL;
  END;
END
$$;

UPDATE public.crm_deal_projection_failures
SET resolved_at = NOW()
WHERE organization_id = 'org_crm_rollout_validation'
  AND resolved_at IS NULL;

SELECT public.enable_crm_pipeline_after_reconciliation('org_crm_rollout_validation', TRUE);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.organization_settings
    WHERE organization_id = 'org_crm_rollout_validation'
      AND crm_pipeline_enabled
      AND crm_automation_enabled
  ) THEN
    RAISE EXCEPTION 'Verified pipeline + automation activation was not persisted';
  END IF;

  IF has_function_privilege(
    'authenticated',
    'public.enable_crm_pipeline_after_reconciliation(text,boolean)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'Authenticated gained direct rollout function access';
  END IF;
END
$$;

SELECT 'crm-deals-rollout-readiness-contract: ok' AS result;

ROLLBACK;
