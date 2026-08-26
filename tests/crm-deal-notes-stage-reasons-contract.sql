\set ON_ERROR_STOP on

-- Run after the CRM deal foundation migrations on a disposable database.
BEGIN;

\ir ../migrations/release_1.3.0/367_crm-deal-notes-and-stage-reasons.sql

INSERT INTO public.organization (id, name)
VALUES ('org_crm_note_validation', 'CRM Note Validation');

INSERT INTO public."user" (id, email)
VALUES ('user_crm_note_validation', 'crm-note-validation@example.com');

INSERT INTO public.user_organizations (user_id, organization_id)
VALUES ('user_crm_note_validation', 'org_crm_note_validation');

INSERT INTO public.companies (id, organization_id, name)
VALUES ('12000000-0000-0000-0000-000000000001', 'org_crm_note_validation', 'Note Company');

INSERT INTO public.contacts (id, organization_id, name, pipeline_stage)
VALUES ('22000000-0000-0000-0000-000000000001', 'org_crm_note_validation', 'Note Contact', 'LEAD');

INSERT INTO public.company_contacts (organization_id, company_id, contact_id)
VALUES (
  'org_crm_note_validation',
  '12000000-0000-0000-0000-000000000001',
  '22000000-0000-0000-0000-000000000001'
);

INSERT INTO public.deals (
  id, organization_id, company_id, primary_contact_id, owner_user_id, name, creation_source
)
VALUES (
  '32000000-0000-0000-0000-000000000001',
  'org_crm_note_validation',
  '12000000-0000-0000-0000-000000000001',
  '22000000-0000-0000-0000-000000000001',
  'user_crm_note_validation',
  'Note Deal',
  'manual'
);

SELECT public.add_crm_deal_note(
  '32000000-0000-0000-0000-000000000001',
  'org_crm_note_validation',
  'user_crm_note_validation',
  'Talked by phone; reconnect in two weeks for the live demo.'
);

DO $$
DECLARE
  v_contact_note_id UUID;
BEGIN
  SELECT id INTO STRICT v_contact_note_id
  FROM public.contact_notes
  WHERE organization_id = 'org_crm_note_validation'
    AND contact_id = '22000000-0000-0000-0000-000000000001'
    AND note_type = 'deal'
    AND content = 'Talked by phone; reconnect in two weeks for the live demo.';

  IF NOT EXISTS (
    SELECT 1
    FROM public.deal_activities
    WHERE deal_id = '32000000-0000-0000-0000-000000000001'
      AND activity_type = 'note'
      AND metadata->>'contact_note_id' = v_contact_note_id::TEXT
      AND metadata->>'content' = 'Talked by phone; reconnect in two weeks for the live demo.'
  ) THEN
    RAISE EXCEPTION 'Deal note was not dual-written atomically';
  END IF;
END
$$;

SELECT public.update_crm_deal(
  '32000000-0000-0000-0000-000000000001',
  'org_crm_note_validation',
  'user_crm_note_validation',
  '{"stage":"MEETING_REQUESTED"}'::JSONB,
  'Prospect asked to reconnect after budget review'
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.deal_activities
    WHERE deal_id = '32000000-0000-0000-0000-000000000001'
      AND activity_type = 'stage_change'
      AND metadata->>'from' = 'LEAD'
      AND metadata->>'to' = 'MEETING_REQUESTED'
      AND metadata->>'reason' = 'Prospect asked to reconnect after budget review'
  ) THEN
    RAISE EXCEPTION 'Stage-change reason was not persisted on the audit row';
  END IF;

  BEGIN
    PERFORM public.update_crm_deal(
      '32000000-0000-0000-0000-000000000001',
      'org_crm_note_validation',
      'user_crm_note_validation',
      '{"amount":1000}'::JSONB,
      'Reason without stage'
    );
    RAISE EXCEPTION 'Reason without stage unexpectedly succeeded';
  EXCEPTION
    WHEN data_exception THEN NULL;
  END;
END
$$;

SELECT 'crm-deal-notes-stage-reasons-contract: ok' AS result;

ROLLBACK;
