\set ON_ERROR_STOP on

-- Run after migration 372. Only synthetic fixtures are used; all roll back.
BEGIN;
SET LOCAL lock_timeout = '2s';
SET LOCAL statement_timeout = '15s';
SET LOCAL app.crm_suppress_notifications = 'true';

INSERT INTO public.organization (id, name) VALUES
  ('org_kan304_delete', 'KAN-304 deletion fixture'),
  ('org_kan304_other', 'KAN-304 isolation fixture');

INSERT INTO public.crm_lists (id, organization_id, name, source) VALUES
  ('30400000-0000-0000-0000-000000000001', 'org_kan304_delete', 'Imported list fixture', 'csv_import');

INSERT INTO public.companies (id, organization_id, name) VALUES
  ('30400000-0000-0000-0000-000000000011', 'org_kan304_delete', 'Imported company one'),
  ('30400000-0000-0000-0000-000000000012', 'org_kan304_delete', 'Imported company two'),
  ('30400000-0000-0000-0000-000000000013', 'org_kan304_other', 'Unrelated company'),
  ('30400000-0000-0000-0000-000000000014', 'org_kan304_delete', 'Company without deals');

INSERT INTO public.contacts (id, organization_id, name, pipeline_stage) VALUES
  ('30400000-0000-0000-0000-000000000021', 'org_kan304_delete', 'Imported contact', NULL);
INSERT INTO public.company_contacts (organization_id, company_id, contact_id) VALUES
  ('org_kan304_delete', '30400000-0000-0000-0000-000000000011', '30400000-0000-0000-0000-000000000021');

INSERT INTO public.crm_raw_records (list_id, organization_id, extracted_company_id, extracted_person_id) VALUES
  ('30400000-0000-0000-0000-000000000001', 'org_kan304_delete', '30400000-0000-0000-0000-000000000011', '30400000-0000-0000-0000-000000000021'),
  ('30400000-0000-0000-0000-000000000001', 'org_kan304_delete', '30400000-0000-0000-0000-000000000012', NULL);

INSERT INTO public.deals (id, organization_id, company_id, name) VALUES
  ('30400000-0000-0000-0000-000000000031', 'org_kan304_delete', '30400000-0000-0000-0000-000000000011', 'Imported deal one'),
  ('30400000-0000-0000-0000-000000000032', 'org_kan304_delete', '30400000-0000-0000-0000-000000000012', 'Imported deal two'),
  ('30400000-0000-0000-0000-000000000033', 'org_kan304_other', '30400000-0000-0000-0000-000000000013', 'Unrelated deal');
-- Closed historical deals on a company must also be cleaned up.
INSERT INTO public.deals (id, organization_id, company_id, name, stage, closed_at) VALUES
  ('30400000-0000-0000-0000-000000000034', 'org_kan304_delete', '30400000-0000-0000-0000-000000000011', 'Historical deal', 'LOST', NOW());

INSERT INTO public.tasks (id, organization_id, title, task_type, status, deal_id, contact_id) VALUES
  ('30400000-0000-0000-0000-000000000041', 'org_kan304_delete', 'Open manual outreach', 'manual_outreach', 'pending', '30400000-0000-0000-0000-000000000031', '30400000-0000-0000-0000-000000000021'),
  ('30400000-0000-0000-0000-000000000042', 'org_kan304_delete', 'Scheduled nurture', 'nurture_reminder', 'scheduled', '30400000-0000-0000-0000-000000000032', NULL),
  ('30400000-0000-0000-0000-000000000043', 'org_kan304_other', 'Unrelated task', 'manual_outreach', 'pending', '30400000-0000-0000-0000-000000000033', NULL),
  ('30400000-0000-0000-0000-000000000044', 'org_kan304_delete', 'Completed historical task', 'manual_outreach', 'completed', '30400000-0000-0000-0000-000000000034', NULL),
  ('30400000-0000-0000-0000-000000000045', 'org_kan304_delete', 'Open LinkedIn task', 'linkedin_connect', 'in_progress', '30400000-0000-0000-0000-000000000031', NULL);

-- Normal task writes must still enforce both organization and company scope.
-- Modal uses this role; the trigger must work without direct execute grants
-- on the internal trigger function.
SET LOCAL ROLE service_role;
DO $$
BEGIN
  BEGIN
    INSERT INTO public.tasks (organization_id, title, task_type, deal_id)
    VALUES ('org_kan304_other', 'Invalid organization', 'manual_outreach', '30400000-0000-0000-0000-000000000031');
    RAISE EXCEPTION 'Cross-organization task was accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  BEGIN
    UPDATE public.tasks SET company_id = '30400000-0000-0000-0000-000000000012'
    WHERE id = '30400000-0000-0000-0000-000000000041';
    RAISE EXCEPTION 'Mismatched company was accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
END;
$$;

-- Mirror CRMService: relationships, contacts, companies, raw records, list.
DELETE FROM public.company_contacts WHERE organization_id = 'org_kan304_delete';
DELETE FROM public.contacts WHERE organization_id = 'org_kan304_delete';
DELETE FROM public.companies WHERE organization_id = 'org_kan304_delete';
DELETE FROM public.crm_raw_records WHERE organization_id = 'org_kan304_delete';
DELETE FROM public.crm_lists WHERE organization_id = 'org_kan304_delete';

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.companies WHERE organization_id = 'org_kan304_delete')
    OR EXISTS (SELECT 1 FROM public.deals WHERE organization_id = 'org_kan304_delete')
    OR EXISTS (SELECT 1 FROM public.crm_lists WHERE organization_id = 'org_kan304_delete')
    OR EXISTS (SELECT 1 FROM public.crm_raw_records WHERE organization_id = 'org_kan304_delete') THEN
    RAISE EXCEPTION 'Imported list or its entities survived deletion';
  END IF;
  IF (SELECT COUNT(*) FROM public.tasks WHERE organization_id = 'org_kan304_delete') <> 4
    OR EXISTS (SELECT 1 FROM public.tasks WHERE organization_id = 'org_kan304_delete' AND (deal_id IS NOT NULL OR company_id IS NOT NULL OR contact_id IS NOT NULL)) THEN
    RAISE EXCEPTION 'Task history was deleted or retained dangling links';
  END IF;
  IF (SELECT COUNT(*) FROM public.tasks WHERE organization_id = 'org_kan304_delete' AND status = 'cancelled' AND metadata->>'cancelled_reason' = 'deal_deleted') <> 3 THEN
    RAISE EXCEPTION 'Open deal workflow tasks were not cancelled';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.tasks WHERE id = '30400000-0000-0000-0000-000000000044' AND status = 'completed') THEN
    RAISE EXCEPTION 'Completed history was changed';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.tasks WHERE id = '30400000-0000-0000-0000-000000000043' AND status = 'pending' AND deal_id = '30400000-0000-0000-0000-000000000033' AND company_id = '30400000-0000-0000-0000-000000000013') THEN
    RAISE EXCEPTION 'Unrelated organization was changed';
  END IF;
END;
$$;

ROLLBACK;
