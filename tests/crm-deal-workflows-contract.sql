\set ON_ERROR_STOP on

-- Run after migrations 344-349 have been applied to a disposable database:
--   psql -X -v ON_ERROR_STOP=1 -f tests/crm-deal-workflows-contract.sql
-- Fixtures and assertions always roll back.
BEGIN;

INSERT INTO public.organization (id, name)
VALUES ('org_crm_workflow_validation', 'CRM Workflow Validation');

INSERT INTO public."user" (id, email)
VALUES
  ('user_crm_workflow_owner_one', 'workflow-owner-one@example.com'),
  ('user_crm_workflow_owner_two', 'workflow-owner-two@example.com');

INSERT INTO public.user_organizations (user_id, organization_id)
VALUES
  ('user_crm_workflow_owner_one', 'org_crm_workflow_validation'),
  ('user_crm_workflow_owner_two', 'org_crm_workflow_validation');

INSERT INTO public.organization_settings (organization_id, default_deal_amount, default_deal_currency, crm_pipeline_enabled)
VALUES ('org_crm_workflow_validation', 12000, 'USD', TRUE);

INSERT INTO public.companies (id, organization_id, name)
VALUES ('11000000-0000-0000-0000-000000000001', 'org_crm_workflow_validation', 'Workflow Company');

INSERT INTO public.contacts (id, organization_id, name, pipeline_stage, assigned_to_user_id)
VALUES (
  '21000000-0000-0000-0000-000000000001',
  'org_crm_workflow_validation',
  'Workflow Contact',
  'LEAD',
  'user_crm_workflow_owner_one'
);

INSERT INTO public.company_contacts (organization_id, company_id, contact_id)
VALUES (
  'org_crm_workflow_validation',
  '11000000-0000-0000-0000-000000000001',
  '21000000-0000-0000-0000-000000000001'
);

DO $$
DECLARE
  v_deal_id UUID;
BEGIN
  SELECT id INTO STRICT v_deal_id
  FROM public.deals
  WHERE organization_id = 'org_crm_workflow_validation'
    AND company_id = '11000000-0000-0000-0000-000000000001'
    AND closed_at IS NULL;

  IF NOT EXISTS (
    SELECT 1
    FROM public.notifications
    WHERE organization_id = 'org_crm_workflow_validation'
      AND user_id = 'user_crm_workflow_owner_one'
      AND type = 'deal_created'
      AND entity_id = v_deal_id::TEXT
  ) THEN
    RAISE EXCEPTION 'Automatic deal creation did not notify its owner';
  END IF;
END
$$;

UPDATE public.contacts
SET pipeline_stage = 'APPOINTMENT_REQUESTED', stage_updated_at = NOW()
WHERE id = '21000000-0000-0000-0000-000000000001';

DO $$
DECLARE
  v_deal_id UUID;
BEGIN
  SELECT id INTO STRICT v_deal_id
  FROM public.deals
  WHERE organization_id = 'org_crm_workflow_validation'
    AND company_id = '11000000-0000-0000-0000-000000000001';

  IF NOT EXISTS (
    SELECT 1
    FROM public.notifications
    WHERE organization_id = 'org_crm_workflow_validation'
      AND user_id = 'user_crm_workflow_owner_one'
      AND type = 'deal_stage_changed'
      AND entity_id = v_deal_id::TEXT
      AND metadata->>'stage' = 'MEETING_REQUESTED'
  ) THEN
    RAISE EXCEPTION 'Automatic stage advancement did not notify its owner';
  END IF;
END
$$;

UPDATE public.organization_settings
SET crm_pipeline_enabled = FALSE
WHERE organization_id = 'org_crm_workflow_validation';

UPDATE public.contacts
SET pipeline_stage = 'APPOINTMENT_SCHEDULED', stage_updated_at = NOW()
WHERE id = '21000000-0000-0000-0000-000000000001';

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.notifications
    WHERE organization_id = 'org_crm_workflow_validation'
      AND type = 'deal_stage_changed'
      AND metadata->>'stage' = 'MEETING_BOOKED'
  ) THEN
    RAISE EXCEPTION 'Dark pipeline unexpectedly emitted a lifecycle notification';
  END IF;
END
$$;

UPDATE public.organization_settings
SET crm_pipeline_enabled = TRUE
WHERE organization_id = 'org_crm_workflow_validation';

DELETE FROM public.organization_settings
WHERE organization_id = 'org_crm_workflow_validation';

UPDATE public.contacts
SET pipeline_stage = 'PRESENTATION_SCHEDULED', stage_updated_at = NOW()
WHERE id = '21000000-0000-0000-0000-000000000001';

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.notifications
    WHERE organization_id = 'org_crm_workflow_validation'
      AND type = 'deal_stage_changed'
      AND metadata->>'stage' = 'PRESENTATION'
  ) THEN
    RAISE EXCEPTION 'Missing pipeline settings unexpectedly emitted a lifecycle notification';
  END IF;
END
$$;

INSERT INTO public.organization_settings (organization_id, default_deal_amount, default_deal_currency, crm_pipeline_enabled)
VALUES ('org_crm_workflow_validation', 12000, 'USD', TRUE);

UPDATE public.deals
SET last_activity_at = NOW() - INTERVAL '20 days'
WHERE organization_id = 'org_crm_workflow_validation';

INSERT INTO public.tasks (
  organization_id,
  created_by_user_id,
  title,
  task_type,
  status,
  contact_id,
  deal_id,
  assigned_to_user_id,
  due_date,
  metadata
)
SELECT
  d.organization_id,
  'system',
  'Reconnect with Workflow Contact',
  'nurture_reminder'::public.task_type,
  'pending'::public.task_status,
  d.primary_contact_id,
  d.id,
  d.owner_user_id,
  NOW(),
  '{"source":"deal_nurture","channel":"email","nurture_cycle":1}'::JSONB
FROM public.deals d
WHERE d.organization_id = 'org_crm_workflow_validation';

DO $$
DECLARE
  v_before TIMESTAMPTZ;
  v_after TIMESTAMPTZ;
BEGIN
  SELECT last_activity_at INTO STRICT v_after
  FROM public.deals
  WHERE organization_id = 'org_crm_workflow_validation';

  v_before := NOW() - INTERVAL '20 days';
  IF v_after > v_before + INTERVAL '1 minute' THEN
    RAISE EXCEPTION 'Creating a nurture task incorrectly bumped last_activity_at';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.deal_activities
    WHERE organization_id = 'org_crm_workflow_validation'
      AND activity_type = 'task_created'
      AND bumps_last_activity = FALSE
  ) THEN
    RAISE EXCEPTION 'Task creation was not projected to deal activities';
  END IF;
END
$$;

DO $$
BEGIN
  BEGIN
    INSERT INTO public.tasks (
      organization_id,
      created_by_user_id,
      title,
      task_type,
      status,
      contact_id,
      deal_id,
      assigned_to_user_id,
      metadata
    )
    SELECT
      d.organization_id,
      'system',
      'Duplicate nurture task',
      'linkedin_connect'::public.task_type,
      'pending'::public.task_status,
      d.primary_contact_id,
      d.id,
      d.owner_user_id,
      '{"source":"deal_nurture","channel":"linkedin"}'::JSONB
    FROM public.deals d
    WHERE d.organization_id = 'org_crm_workflow_validation';

    RAISE EXCEPTION 'Duplicate open nurture task was accepted';
  EXCEPTION WHEN unique_violation THEN
    NULL;
  END;
END
$$;

UPDATE public.tasks
SET status = 'completed'::public.task_status,
    completed_at = NOW(),
    completed_by_user_id = 'user_crm_workflow_owner_one'
WHERE organization_id = 'org_crm_workflow_validation'
  AND task_type = 'nurture_reminder'::public.task_type;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.deals
    WHERE organization_id = 'org_crm_workflow_validation'
      AND last_activity_at > NOW() - INTERVAL '1 minute'
  ) THEN
    RAISE EXCEPTION 'Completing a deal task did not reset last_activity_at';
  END IF;

  IF (
    SELECT COUNT(*)
    FROM public.deal_activities
    WHERE organization_id = 'org_crm_workflow_validation'
      AND activity_type = 'task_completed'
  ) <> 1 THEN
    RAISE EXCEPTION 'Task completion activity is not idempotent';
  END IF;
END
$$;

SELECT public.record_crm_deal_activity_for_contact(
  'org_crm_workflow_validation',
  '21000000-0000-0000-0000-000000000001',
  'linkedin_in',
  'LinkedIn reply received',
  'linkedin:workflow-message-one',
  '{"message_id":"workflow-message-one"}'::JSONB,
  NOW(),
  'system',
  NULL
);

SELECT public.record_crm_deal_activity_for_contact(
  'org_crm_workflow_validation',
  '21000000-0000-0000-0000-000000000001',
  'linkedin_in',
  'LinkedIn reply received',
  'linkedin:workflow-message-one',
  '{"message_id":"workflow-message-one"}'::JSONB,
  NOW(),
  'system',
  NULL
);

DO $$
BEGIN
  IF (
    SELECT COUNT(*)
    FROM public.deal_activities
    WHERE organization_id = 'org_crm_workflow_validation'
      AND source_event_key = 'linkedin:workflow-message-one'
  ) <> 1 THEN
    RAISE EXCEPTION 'Provider event activity deduplication failed';
  END IF;
END
$$;

INSERT INTO public.tasks (
  organization_id,
  created_by_user_id,
  title,
  task_type,
  status,
  contact_id,
  deal_id,
  assigned_to_user_id,
  metadata
)
SELECT
  d.organization_id,
  'user_crm_workflow_owner_one',
  'Manual email tomorrow',
  'manual_outreach'::public.task_type,
  'pending'::public.task_status,
  d.primary_contact_id,
  d.id,
  d.owner_user_id,
  '{"source":"manual","channel":"email"}'::JSONB
FROM public.deals d
WHERE d.organization_id = 'org_crm_workflow_validation';

DO $$
DECLARE
  v_deal_id UUID;
BEGIN
  SELECT id INTO STRICT v_deal_id
  FROM public.deals
  WHERE organization_id = 'org_crm_workflow_validation';

  PERFORM public.update_crm_deal(
    v_deal_id,
    'org_crm_workflow_validation',
    'user_crm_workflow_owner_one',
    '{"owner_user_id":"user_crm_workflow_owner_two"}'::JSONB
  );

  IF EXISTS (
    SELECT 1
    FROM public.tasks
    WHERE deal_id = v_deal_id
      AND status = 'pending'::public.task_status
      AND assigned_to_user_id IS DISTINCT FROM 'user_crm_workflow_owner_two'
  ) THEN
    RAISE EXCEPTION 'Open deal tasks were not transferred with the deal owner';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.notifications
    WHERE organization_id = 'org_crm_workflow_validation'
      AND user_id = 'user_crm_workflow_owner_two'
      AND type = 'deal_owner_changed'
      AND entity_id = v_deal_id::TEXT
  ) THEN
    RAISE EXCEPTION 'Deal owner transfer notification was not created';
  END IF;
END
$$;

DO $$
DECLARE
  v_deal_id UUID;
BEGIN
  SELECT id INTO STRICT v_deal_id
  FROM public.deals
  WHERE organization_id = 'org_crm_workflow_validation';

  BEGIN
    INSERT INTO public.tasks (
      organization_id,
      created_by_user_id,
      title,
      task_type,
      status,
      deal_id,
      company_id,
      metadata
    ) VALUES (
      'org_crm_workflow_validation',
      'system',
      'Mismatched company task',
      'manual_outreach'::public.task_type,
      'pending'::public.task_status,
      v_deal_id,
      '11000000-0000-0000-0000-000000000099',
      '{}'::JSONB
    );

    RAISE EXCEPTION 'Task/deal company scope mismatch was accepted';
  EXCEPTION WHEN foreign_key_violation OR check_violation THEN
    NULL;
  END;
END
$$;

INSERT INTO public.companies (id, organization_id, name)
VALUES ('11000000-0000-0000-0000-000000000002', 'org_crm_workflow_validation', 'Manual Workflow Company');

INSERT INTO public.contacts (id, organization_id, name, pipeline_stage, assigned_to_user_id)
VALUES (
  '21000000-0000-0000-0000-000000000002',
  'org_crm_workflow_validation',
  'Manual Workflow Contact',
  'PROSPECT',
  'user_crm_workflow_owner_one'
);

INSERT INTO public.company_contacts (organization_id, company_id, contact_id)
VALUES (
  'org_crm_workflow_validation',
  '11000000-0000-0000-0000-000000000002',
  '21000000-0000-0000-0000-000000000002'
);

DO $$
DECLARE
  v_manual_deal public.deals;
BEGIN
  v_manual_deal := public.create_crm_deal(
    'org_crm_workflow_validation',
    '11000000-0000-0000-0000-000000000002',
    '21000000-0000-0000-0000-000000000002',
    NULL,
    'user_crm_workflow_owner_one',
    NULL,
    'LEAD',
    5000,
    'EUR',
    'user_crm_workflow_owner_one'
  );

  IF v_manual_deal.creation_source <> 'manual'
    OR v_manual_deal.name <> 'Manual Workflow Company'
    OR v_manual_deal.amount <> 5000
    OR v_manual_deal.currency <> 'EUR' THEN
    RAISE EXCEPTION 'Manual deal RPC returned the wrong contract: %', ROW_TO_JSON(v_manual_deal);
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.deal_activities
    WHERE deal_id = v_manual_deal.id
      AND activity_type = 'deal_created'
      AND actor = 'user'
      AND actor_user_id = 'user_crm_workflow_owner_one'
  ) THEN
    RAISE EXCEPTION 'Manual deal creation did not preserve user audit context';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.notifications
    WHERE entity_id = v_manual_deal.id::TEXT
      AND type = 'deal_created'
      AND user_id = 'user_crm_workflow_owner_one'
  ) THEN
    RAISE EXCEPTION 'Manual deal creation did not notify the owner';
  END IF;

  BEGIN
    PERFORM public.create_crm_deal(
      'org_crm_workflow_validation',
      '11000000-0000-0000-0000-000000000002',
      '21000000-0000-0000-0000-000000000002',
      NULL,
      'user_crm_workflow_owner_one',
      NULL,
      'LEAD',
      NULL,
      'USD',
      'user_crm_workflow_owner_one'
    );
    RAISE EXCEPTION 'Manual RPC accepted a second open deal for one company';
  EXCEPTION WHEN unique_violation THEN
    NULL;
  END;
END
$$;

SELECT 'crm-deal-workflows-contract: ok' AS result;

ROLLBACK;
