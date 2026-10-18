-- KAN-334 local test for migrations 400/401. Runs against a throwaway Postgres loaded with
-- full_schema.sql plus the later migrations (see README.md next to this file). Never run it on stage or
-- production: it inserts and deletes rows. Every check is an ASSERT; the script stops at the first failure.
\set ON_ERROR_STOP 1

INSERT INTO organization (id, name) VALUES ('org_t', 'Test Org'), ('org_x', 'Other Org') ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------------------------------
-- Delete: a list of 250 owned companies + 1 matched existing company, people in every shape.
-- ---------------------------------------------------------------------------------------------
DO $$
DECLARE
  v_list uuid := '11111111-0000-0000-0000-000000000001';
  v_list_x uuid := '11111111-0000-0000-0000-000000000002';
  v_campaign uuid := '22222222-0000-0000-0000-000000000001';
  v_outside uuid := '33333333-0000-0000-0000-000000000001';
  v_existing uuid := '33333333-0000-0000-0000-000000000002';
  v_xcompany uuid := '33333333-0000-0000-0000-000000000003';
  i integer;
BEGIN
  INSERT INTO crm_lists (id, organization_id, name, source) VALUES
    (v_list, 'org_t', 'Big list', 'csv_import'),
    (v_list_x, 'org_x', 'Other org list', 'csv_import');
  INSERT INTO campaigns (id, organization_id, user_id, name, status) VALUES (v_campaign, 'org_t', 'user_1', 'Live A', 'active');

  FOR i IN 1..250 LOOP
    INSERT INTO companies (id, organization_id, name, crm_list_id, processing_status)
    VALUES (('44444444-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid, 'org_t', 'List Co ' || i, v_list::text, 'imported');
    INSERT INTO crm_raw_records (list_id, organization_id, record_type, extracted_company_id, import_status)
    VALUES (v_list, 'org_t', 'company', ('44444444-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid, 'extracted');
  END LOOP;

  INSERT INTO companies (id, organization_id, name, processing_status) VALUES
    (v_outside, 'org_t', 'Outside Co', 'processed'),
    (v_existing, 'org_t', 'Existing Co matched by name', 'approved');
  INSERT INTO companies (id, organization_id, name, crm_list_id) VALUES (v_xcompany, 'org_x', 'Other org co', v_list::text);
  INSERT INTO crm_raw_records (list_id, organization_id, record_type, extracted_company_id, import_status)
  VALUES (v_list, 'org_t', 'company', v_existing, 'extracted');

  -- P1 at list company 1 only: deleted. P2 at list company 2 and outside: kept.
  -- P3 list person with no company: deleted in the person phase. P4 list person at the outside company: kept.
  -- P5 other org: untouched. P6 at list company 1 and list company 200 (different batches): deleted.
  INSERT INTO contacts (id, organization_id, name) VALUES
    ('55555555-0000-0000-0000-000000000001', 'org_t', 'P1'),
    ('55555555-0000-0000-0000-000000000002', 'org_t', 'P2'),
    ('55555555-0000-0000-0000-000000000003', 'org_t', 'P3'),
    ('55555555-0000-0000-0000-000000000004', 'org_t', 'P4'),
    ('55555555-0000-0000-0000-000000000005', 'org_x', 'P5'),
    ('55555555-0000-0000-0000-000000000006', 'org_t', 'P6');
  INSERT INTO company_contacts (company_id, contact_id, organization_id) VALUES
    ('44444444-0000-0000-0000-000000000001', '55555555-0000-0000-0000-000000000001', 'org_t'),
    ('44444444-0000-0000-0000-000000000002', '55555555-0000-0000-0000-000000000002', 'org_t'),
    (v_outside, '55555555-0000-0000-0000-000000000002', 'org_t'),
    (v_outside, '55555555-0000-0000-0000-000000000004', 'org_t'),
    ('44444444-0000-0000-0000-000000000001', '55555555-0000-0000-0000-000000000006', 'org_t'),
    ('44444444-0000-0000-0000-000000000200', '55555555-0000-0000-0000-000000000006', 'org_t'),
    (v_xcompany, '55555555-0000-0000-0000-000000000005', 'org_x');
  INSERT INTO crm_raw_records (list_id, organization_id, record_type, extracted_person_id, import_status) VALUES
    (v_list, 'org_t', 'person', '55555555-0000-0000-0000-000000000003', 'extracted'),
    (v_list, 'org_t', 'person', '55555555-0000-0000-0000-000000000004', 'extracted');

  -- Live work on list company 1 / P1: campaign link, pending review, journey with an open action, reply draft, deal.
  INSERT INTO campaign_companies (campaign_id, company_id, organization_id, status)
  VALUES (v_campaign, '44444444-0000-0000-0000-000000000001', 'org_t', 'approved');
  INSERT INTO tasks (id, organization_id, title, task_type, status, company_id, campaign_id) VALUES
    ('66666666-0000-0000-0000-000000000001', 'org_t', 'Review List Co 3', 'company_verification', 'pending',
     '44444444-0000-0000-0000-000000000003', v_campaign),
    ('66666666-0000-0000-0000-000000000002', 'org_t', 'Draft for P1', 'review_draft', 'pending',
     NULL, v_campaign);
  UPDATE tasks SET contact_id = '55555555-0000-0000-0000-000000000001' WHERE id = '66666666-0000-0000-0000-000000000002';
  INSERT INTO campaign_contacts (id, campaign_id, contact_id, organization_id, owner_user_id, journey_state) VALUES
    ('77777777-0000-0000-0000-000000000001', v_campaign, '55555555-0000-0000-0000-000000000001', 'org_t', 'user_1', 'invited'),
    ('77777777-0000-0000-0000-000000000002', v_campaign, '55555555-0000-0000-0000-000000000002', 'org_t', 'user_1', 'invited');
  INSERT INTO campaign_sequence_actions (campaign_contact_id, channel, action_type, status) VALUES
    ('77777777-0000-0000-0000-000000000001', 'linkedin', 'linkedin_message', 'pending'),
    ('77777777-0000-0000-0000-000000000001', 'linkedin', 'linkedin_invitation', 'executed'),
    ('77777777-0000-0000-0000-000000000002', 'linkedin', 'linkedin_message', 'pending');
  INSERT INTO reply_drafts (organization_id, message_id, channel, contact_id, drafted_body, status)
  VALUES ('org_t', gen_random_uuid(), 'linkedin', '55555555-0000-0000-0000-000000000001', 'Hi', 'draft');
  INSERT INTO deals (organization_id, company_id, name) VALUES ('org_t', '44444444-0000-0000-0000-000000000004', 'Deal on List Co 4');
END $$;

-- Preview counts.
DO $$
DECLARE p jsonb;
BEGIN
  p := crm_list_delete_preview('org_t', '11111111-0000-0000-0000-000000000001');
  RAISE NOTICE 'preview %', p;
  ASSERT (p->>'companies')::int = 251, 'preview companies';
  ASSERT (p->>'contacts')::int = 3, 'preview contacts: P1, P3, P6';
  ASSERT (p->>'companies_in_campaigns')::int = 1, 'preview companies_in_campaigns';
  ASSERT (p->>'companies_with_deals')::int = 1, 'preview companies_with_deals';
  ASSERT (p->>'contacts_in_sequences')::int = 1, 'preview contacts_in_sequences';
  ASSERT (crm_list_delete_preview('org_x', '11111111-0000-0000-0000-000000000001')->>'list_found')::boolean = false, 'preview other org';
END $$;

-- Wrong org, bad limit.
DO $$
BEGIN
  ASSERT (crm_list_delete_batch('org_x', '11111111-0000-0000-0000-000000000001', 100)->>'list_found')::boolean = false, 'batch other org';
  BEGIN
    PERFORM crm_list_delete_batch('org_t', '11111111-0000-0000-0000-000000000001', 0);
    ASSERT false, 'limit 0 must raise';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
END $$;

-- The job loop.
DO $$
DECLARE
  r jsonb;
  n integer := 0;
  companies_total integer := 0;
  contacts_total integer := 0;
BEGIN
  LOOP
    r := crm_list_delete_batch('org_t', '11111111-0000-0000-0000-000000000001', 100);
    n := n + 1;
    companies_total := companies_total + (r->>'deleted_companies')::int;
    contacts_total := contacts_total + (r->>'deleted_contacts')::int;
    EXIT WHEN (r->>'deleted_companies')::int + (r->>'deleted_contacts')::int = 0 OR n > 50;
  END LOOP;
  RAISE NOTICE 'batches % companies % contacts %', n, companies_total, contacts_total;
  ASSERT companies_total = 251, 'all list companies deleted';
  ASSERT contacts_total = 3, 'P1, P3 and P6 deleted';
  ASSERT n = 5, 'three company batches, one person batch, one empty';
END $$;

DO $$
BEGIN
  ASSERT NOT EXISTS (SELECT 1 FROM companies WHERE organization_id = 'org_t' AND crm_list_id = '11111111-0000-0000-0000-000000000001'), 'owned companies gone';
  ASSERT NOT EXISTS (SELECT 1 FROM companies WHERE id = '33333333-0000-0000-0000-000000000002'), 'matched existing company gone (D1)';
  ASSERT EXISTS (SELECT 1 FROM companies WHERE id = '33333333-0000-0000-0000-000000000001'), 'outside company kept';
  ASSERT EXISTS (SELECT 1 FROM companies WHERE id = '33333333-0000-0000-0000-000000000003'), 'other org company kept';
  ASSERT NOT EXISTS (SELECT 1 FROM contacts WHERE id IN ('55555555-0000-0000-0000-000000000001', '55555555-0000-0000-0000-000000000003', '55555555-0000-0000-0000-000000000006')), 'P1 P3 P6 gone';
  ASSERT (SELECT count(*) FROM contacts WHERE id IN ('55555555-0000-0000-0000-000000000002', '55555555-0000-0000-0000-000000000004', '55555555-0000-0000-0000-000000000005')) = 3, 'P2 P4 P5 kept';
  ASSERT EXISTS (SELECT 1 FROM company_contacts WHERE contact_id = '55555555-0000-0000-0000-000000000002' AND company_id = '33333333-0000-0000-0000-000000000001'), 'P2 outside link kept';
  ASSERT (SELECT journey_state FROM campaign_contacts WHERE id = '77777777-0000-0000-0000-000000000001') = 'cancelled', 'P1 journey cancelled';
  ASSERT (SELECT state_metadata->>'cancel_reason' FROM campaign_contacts WHERE id = '77777777-0000-0000-0000-000000000001') = 'contact_deleted', 'P1 journey reason';
  ASSERT (SELECT journey_state FROM campaign_contacts WHERE id = '77777777-0000-0000-0000-000000000002') = 'invited', 'P2 journey untouched';
  ASSERT (SELECT count(*) FROM campaign_sequence_actions a WHERE a.campaign_contact_id = '77777777-0000-0000-0000-000000000001' AND a.status = 'cancelled') = 1, 'P1 open action cancelled';
  ASSERT (SELECT count(*) FROM campaign_sequence_actions a WHERE a.campaign_contact_id = '77777777-0000-0000-0000-000000000001' AND a.status = 'executed') = 1, 'P1 executed action kept';
  ASSERT (SELECT status FROM campaign_sequence_actions WHERE campaign_contact_id = '77777777-0000-0000-0000-000000000002') = 'pending', 'P2 action untouched';
  ASSERT (SELECT status FROM reply_drafts WHERE contact_id = '55555555-0000-0000-0000-000000000001') = 'rejected', 'P1 draft rejected';
  ASSERT (SELECT status::text || '/' || (metadata->>'cancelled_reason') FROM tasks WHERE id = '66666666-0000-0000-0000-000000000001') = 'cancelled/company_deleted', 'review task cancelled';
  ASSERT (SELECT status::text || '/' || (metadata->>'cancelled_reason') FROM tasks WHERE id = '66666666-0000-0000-0000-000000000002') = 'cancelled/contact_deleted', 'draft task cancelled';
  ASSERT NOT EXISTS (SELECT 1 FROM deals WHERE name = 'Deal on List Co 4'), 'deal gone with its company';
  ASSERT NOT EXISTS (SELECT 1 FROM campaign_companies WHERE company_id = '44444444-0000-0000-0000-000000000001'), 'campaign link gone';
  ASSERT (SELECT count(*) FROM crm_raw_records WHERE list_id = '11111111-0000-0000-0000-000000000001') = 253, 'raw records stay for the job to delete';
  ASSERT (crm_list_delete_batch('org_t', '11111111-0000-0000-0000-000000000001', 100)->>'deleted_companies')::int = 0, 'finished list returns 0 again';
END $$;

-- ---------------------------------------------------------------------------------------------
-- Move.
-- ---------------------------------------------------------------------------------------------
DO $$
DECLARE
  a uuid := 'aaaaaaaa-0000-0000-0000-00000000000a';
  b uuid := 'aaaaaaaa-0000-0000-0000-00000000000b';
  c uuid := 'aaaaaaaa-0000-0000-0000-00000000000c';
  d uuid := 'aaaaaaaa-0000-0000-0000-00000000000d';
  x uuid := 'aaaaaaaa-0000-0000-0000-0000000000ff';
  i integer;
BEGIN
  INSERT INTO campaigns (id, organization_id, user_id, name, status) VALUES
    (a, 'org_t', 'user_1', 'Camp A', 'active'),
    (b, 'org_t', 'user_1', 'Camp B', 'paused'),
    (c, 'org_t', 'user_1', 'Camp C', 'active'),
    (d, 'org_t', 'user_1', 'Camp D', 'completed'),
    (x, 'org_x', 'user_9', 'Other org camp', 'active');
  FOR i IN 1..10 LOOP
    INSERT INTO companies (id, organization_id, name, processing_status, blocked_by_icp)
    VALUES (('bbbbbbbb-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid, 'org_t', 'Move Co ' || i, 'processed', false);
    INSERT INTO campaign_companies (campaign_id, company_id, organization_id, status, processing_status)
    VALUES (a, ('bbbbbbbb-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid, 'org_t', 'pending', 'completed');
    INSERT INTO tasks (organization_id, title, task_type, status, company_id, campaign_id)
    VALUES ('org_t', 'Review Move Co ' || i, 'company_verification', 'pending',
            ('bbbbbbbb-0000-0000-0000-' || lpad(i::text, 12, '0'))::uuid, a);
  END LOOP;
  -- Co 2 also in live campaign C; Co 4 declined in B; Co 5 approved globally; Co 6 task done;
  -- Co 8 already pending with a pending review in B; Co 9 had a cancelled review in B; Co 10 for the race.
  INSERT INTO campaign_companies (campaign_id, company_id, organization_id, status) VALUES
    (c, 'bbbbbbbb-0000-0000-0000-000000000002', 'org_t', 'pending'),
    (b, 'bbbbbbbb-0000-0000-0000-000000000004', 'org_t', 'rejected'),
    (b, 'bbbbbbbb-0000-0000-0000-000000000008', 'org_t', 'pending'),
    (b, 'bbbbbbbb-0000-0000-0000-000000000009', 'org_t', 'pending');
  UPDATE companies SET processing_status = 'approved' WHERE id = 'bbbbbbbb-0000-0000-0000-000000000005';
  UPDATE tasks SET status = 'completed' WHERE company_id = 'bbbbbbbb-0000-0000-0000-000000000006';
  INSERT INTO tasks (organization_id, title, task_type, status, company_id, campaign_id) VALUES
    ('org_t', 'Review Move Co 8 in B', 'company_verification', 'pending', 'bbbbbbbb-0000-0000-0000-000000000008', b),
    ('org_t', 'Review Move Co 9 in B', 'company_verification', 'cancelled', 'bbbbbbbb-0000-0000-0000-000000000009', b);
END $$;

DO $$
DECLARE
  a uuid := 'aaaaaaaa-0000-0000-0000-00000000000a';
  b uuid := 'aaaaaaaa-0000-0000-0000-00000000000b';
  d uuid := 'aaaaaaaa-0000-0000-0000-00000000000d';
  x uuid := 'aaaaaaaa-0000-0000-0000-0000000000ff';
  r jsonb;
BEGIN
  r := move_company_review('org_t', 'bbbbbbbb-0000-0000-0000-000000000001', a, b, 'user_1');
  RAISE NOTICE 'move 1 %', r;
  ASSERT (r->>'ok')::boolean AND r->>'target_status' = 'paused' AND (r->>'rescore')::boolean, 'move 1 ok';
  ASSERT NOT EXISTS (SELECT 1 FROM campaign_companies WHERE campaign_id = a AND company_id = 'bbbbbbbb-0000-0000-0000-000000000001'), 'source link gone';
  ASSERT (SELECT status || '/' || processing_status || '/' || moved_from_campaign_id::text || '/' || moved_by
          FROM campaign_companies WHERE campaign_id = b AND company_id = 'bbbbbbbb-0000-0000-0000-000000000001')
         = 'pending/pending/' || a::text || '/user_1', 'target link';
  ASSERT (SELECT status::text || '/' || (metadata->>'moved_to_campaign_id') FROM tasks
          WHERE company_id = 'bbbbbbbb-0000-0000-0000-000000000001' AND campaign_id = a) = 'cancelled/' || b::text, 'source task cancelled';
  ASSERT (SELECT processing_status FROM companies WHERE id = 'bbbbbbbb-0000-0000-0000-000000000001') = 'scheduled', 'company rescheduled';
  ASSERT (SELECT title FROM company_activities WHERE company_id = 'bbbbbbbb-0000-0000-0000-000000000001') = 'Moved from Camp A to Camp B', 'activity';

  ASSERT move_company_review('org_t', 'bbbbbbbb-0000-0000-0000-000000000001', a, b, 'user_1')->>'code' = 'already_moved', 'second move';
  ASSERT move_company_review('org_t', 'bbbbbbbb-0000-0000-0000-000000000002', a, b, 'user_1')->>'code' = 'in_other_campaign', 'other live campaign';
  ASSERT move_company_review('org_t', 'bbbbbbbb-0000-0000-0000-000000000003', a, d, 'user_1')->>'code' = 'target_not_allowed', 'completed target';
  ASSERT move_company_review('org_t', 'bbbbbbbb-0000-0000-0000-000000000003', a, a, 'user_1')->>'code' = 'same_campaign', 'same campaign';
  ASSERT move_company_review('org_t', 'bbbbbbbb-0000-0000-0000-000000000003', a, x, 'user_1')->>'code' = 'not_found', 'other org target';
  ASSERT move_company_review('org_x', 'bbbbbbbb-0000-0000-0000-000000000003', a, b, 'user_1')->>'code' = 'not_found', 'wrong org';
  ASSERT move_company_review('org_t', 'bbbbbbbb-0000-0000-0000-000000000004', a, b, 'user_1')->>'code' = 'declined_in_target', 'declined link in target';
  ASSERT move_company_review('org_t', 'bbbbbbbb-0000-0000-0000-000000000005', a, b, 'user_1')->>'code' = 'company_busy', 'approved company';
  ASSERT move_company_review('org_t', 'bbbbbbbb-0000-0000-0000-000000000006', a, b, 'user_1')->>'code' = 'source_not_pending', 'task done';
  ASSERT move_company_review('org_t', 'bbbbbbbb-0000-0000-0000-000000000009', a, b, 'user_1')->>'code' = 'declined_in_target', 'earlier review in target';

  r := move_company_review('org_t', 'bbbbbbbb-0000-0000-0000-000000000008', a, b, 'user_1');
  ASSERT (r->>'ok')::boolean AND NOT (r->>'rescore')::boolean, 'pending review already in target: withdraw only';
  ASSERT (SELECT processing_status FROM companies WHERE id = 'bbbbbbbb-0000-0000-0000-000000000008') = 'processed', 'no rescore';
  ASSERT (SELECT count(*) FROM campaign_companies WHERE company_id = 'bbbbbbbb-0000-0000-0000-000000000008') = 1, 'one link left';

  -- Refusals write nothing.
  ASSERT (SELECT count(*) FROM campaign_companies WHERE company_id = 'bbbbbbbb-0000-0000-0000-000000000003' AND campaign_id = a AND status = 'pending') = 1, 'refused: link untouched';
  ASSERT (SELECT status::text FROM tasks WHERE company_id = 'bbbbbbbb-0000-0000-0000-000000000003') = 'pending', 'refused: task untouched';
END $$;

-- ---------------------------------------------------------------------------------------------
-- Grants: the browser keys cannot call the functions.
-- ---------------------------------------------------------------------------------------------
DO $$
DECLARE r text;
BEGIN
  FOR r IN SELECT unnest(ARRAY['anon', 'authenticated']) LOOP
    ASSERT NOT has_function_privilege(r, 'public.crm_list_delete_batch(text, uuid, integer)', 'EXECUTE'), r || ' batch';
    ASSERT NOT has_function_privilege(r, 'public.crm_list_delete_preview(text, uuid)', 'EXECUTE'), r || ' preview';
    ASSERT NOT has_function_privilege(r, 'public.move_company_review(text, uuid, uuid, uuid, text)', 'EXECUTE'), r || ' move';
  END LOOP;
  ASSERT has_function_privilege('service_role', 'public.move_company_review(text, uuid, uuid, uuid, text)', 'EXECUTE'), 'service_role move';
  ASSERT NOT has_table_privilege('anon', 'public.crm_list_delete_jobs', 'SELECT'), 'anon jobs table';
END $$;

-- One open delete job per list.
DO $$
BEGIN
  INSERT INTO crm_list_delete_jobs (organization_id, list_id, status) VALUES ('org_t', '11111111-0000-0000-0000-000000000001', 'deleting');
  BEGIN
    INSERT INTO crm_list_delete_jobs (organization_id, list_id, status) VALUES ('org_t', '11111111-0000-0000-0000-000000000001', 'queued');
    ASSERT false, 'second open job must fail';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
  UPDATE crm_list_delete_jobs SET status = 'failed' WHERE list_id = '11111111-0000-0000-0000-000000000001';
  INSERT INTO crm_list_delete_jobs (organization_id, list_id, status) VALUES ('org_t', '11111111-0000-0000-0000-000000000001', 'queued');
END $$;

SELECT 'ALL KAN-334 FUNCTION CHECKS PASSED' AS result;
