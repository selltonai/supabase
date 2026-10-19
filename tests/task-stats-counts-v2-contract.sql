-- KAN-322 FR-B5e: task_stats_counts_v2 (408) counts with the task list's rule; v1 (386) stays as it was.
-- Disposable database only. Each expected value is worked out by hand beside its fixture.
INSERT INTO public.campaigns VALUES
  ('00000000-0000-0000-0000-0000000000c1', 'org_a', 'active'),
  ('00000000-0000-0000-0000-0000000000c2', 'org_a', 'paused');
INSERT INTO public.campaign_companies VALUES
  ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000f1', 'org_a', 'approved');
INSERT INTO public.contacts VALUES ('00000000-0000-0000-0000-0000000000a1', false), ('00000000-0000-0000-0000-0000000000a2', true);

-- t1 an email draft, approved, due 2026-10-18 (overdue on 10-19)      -> Emails, review bucket
-- t2 a LinkedIn draft, approved, due 2026-10-19 10:00                -> LinkedIn
-- t3 a LinkedIn reply (review_reply), positive, due 2026-10-19 12:00  -> LinkedIn, a reply
-- t4 a company approval carrying email_type 'reply', due 2026-10-19   -> Companies; a "reply" by the clause
-- t5 a meeting carrying email_type 'reply', no due date               -> Meetings; a "reply" by the clause
-- t6 manual outreach on LinkedIn, no deal                             -> "other"; the LinkedIn pill must not count it
-- t7 an email draft whose company is not approved                     -> hidden
-- t8 an email draft for a do-not-contact person                      -> hidden
-- t9 a LinkedIn reply in a paused play (a reply drains while paused)  -> LinkedIn, a reply
-- t10 an email draft, approved, completed, due 2026-10-20             -> Emails (completed)
-- t11 the other org's draft                                           -> never counted
INSERT INTO public.tasks (id, organization_id, task_type, status, priority, contact_id, campaign_id, company_id, deal_id, due_date, metadata) VALUES
  ('00000000-0000-0000-0000-000000000001', 'org_a', 'review_draft', 'pending', 'high', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000f1', NULL, '2026-10-18T09:00Z', '{"channel":"email"}'),
  ('00000000-0000-0000-0000-000000000002', 'org_a', 'review_draft', 'pending', 'normal', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000f1', NULL, '2026-10-19T10:00Z', '{"channel":"linkedin"}'),
  ('00000000-0000-0000-0000-000000000003', 'org_a', 'review_reply', 'pending', 'normal', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000c1', NULL, NULL, '2026-10-19T12:00Z', '{"channel":"linkedin","sentiment":"positive"}'),
  ('00000000-0000-0000-0000-000000000004', 'org_a', 'company_verification', 'pending', 'normal', NULL, '00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000f1', NULL, '2026-10-19T08:00Z', '{"email_type":"reply"}'),
  ('00000000-0000-0000-0000-000000000005', 'org_a', 'meeting', 'pending', 'normal', '00000000-0000-0000-0000-0000000000a1', NULL, NULL, NULL, NULL, '{"email_type":"reply"}'),
  ('00000000-0000-0000-0000-000000000006', 'org_a', 'manual_outreach', 'pending', 'normal', '00000000-0000-0000-0000-0000000000a1', NULL, NULL, NULL, NULL, '{"channel":"linkedin"}'),
  ('00000000-0000-0000-0000-000000000007', 'org_a', 'review_draft', 'pending', 'normal', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000f2', NULL, NULL, '{"channel":"email"}'),
  ('00000000-0000-0000-0000-000000000008', 'org_a', 'review_draft', 'pending', 'normal', '00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000f1', NULL, NULL, '{"channel":"email"}'),
  ('00000000-0000-0000-0000-000000000009', 'org_a', 'review_reply', 'pending', 'normal', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000c2', NULL, NULL, NULL, '{"channel":"linkedin","sentiment":"NEGATIVE"}'),
  ('00000000-0000-0000-0000-00000000000a', 'org_a', 'review_draft', 'completed', 'normal', '00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000f1', NULL, '2026-10-20T09:00Z', '{"channel":"email"}'),
  ('00000000-0000-0000-0000-00000000000b', 'org_b', 'review_draft', 'pending', 'normal', NULL, NULL, NULL, NULL, '2026-10-18T09:00Z', '{"channel":"email"}');

-- count(v, args): the number of tasks for a call of v1 or v2 (sum over the groups).
CREATE FUNCTION pg_temp.total(v int, p_status text DEFAULT NULL, p_task_type text DEFAULT NULL, p_channel text DEFAULT NULL,
  p_reply text DEFAULT NULL, p_due_from timestamptz DEFAULT NULL, p_due_before timestamptz DEFAULT NULL) RETURNS bigint
LANGUAGE plpgsql AS $$
DECLARE n bigint;
BEGIN
  IF v = 1 THEN
    SELECT coalesce(sum(tasks), 0) INTO n FROM public.task_stats_counts_v1('org_a', p_status, p_task_type, NULL, NULL, NULL, NULL, false, p_channel, p_reply, NULL);
  ELSE
    SELECT coalesce(sum(tasks), 0) INTO n FROM public.task_stats_counts_v2('org_a', p_status, p_task_type, NULL, NULL, NULL, NULL, false, p_channel, p_reply, NULL, p_due_from, p_due_before);
  END IF;
  RETURN n;
END $$;

CREATE FUNCTION pg_temp.expect(label text, got bigint, want bigint) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF got IS DISTINCT FROM want THEN RAISE EXCEPTION '%: got %, want %', label, got, want; END IF;
END $$;

-- Visible in org_a: t1 t2 t3 t4 t5 t6 t9 (pending) and t10 (completed). t7 t8 hidden, t11 another org.
SELECT pg_temp.expect('v2, no filter, every status', pg_temp.total(2), 8);
SELECT pg_temp.expect('v1 and v2 agree without type, channel or due', pg_temp.total(1), pg_temp.total(2));
SELECT pg_temp.expect('v2 pending', pg_temp.total(2, 'pending'), 7);

-- 1. A type under a reply filter. The list keeps company_verification / meeting: replies among them only (t4 / t5).
--    v1 dropped the type and counted every reply (t3, t4, t5, t9).
SELECT pg_temp.expect('v2 Companies + replies', pg_temp.total(2, NULL, 'company_verification', NULL, 'replies_all'), 1);
SELECT pg_temp.expect('v2 Meetings + replies', pg_temp.total(2, NULL, 'meeting', NULL, 'replies_all'), 1);
SELECT pg_temp.expect('v1 Companies + replies (the old rule)', pg_temp.total(1, NULL, 'company_verification', NULL, 'replies_all'), 4);
--    A review type still gives way to the reply clause: review_draft + replies = every reply (t3, t4, t5, t9).
SELECT pg_temp.expect('v2 review_draft + replies', pg_temp.total(2, NULL, 'review_draft', NULL, 'replies_all'), 4);
SELECT pg_temp.expect('v2 review_draft + positive', pg_temp.total(2, NULL, 'review_draft', NULL, 'replies_positive'), 1);

-- 2. A channel pill outside the CRM source: review drafts and replies only. LinkedIn = t2 t3 t9 (not t6).
SELECT pg_temp.expect('v2 LinkedIn pill', pg_temp.total(2, NULL, NULL, 'linkedin'), 3);
SELECT pg_temp.expect('v1 LinkedIn pill (the old rule)', pg_temp.total(1, NULL, NULL, 'linkedin'), 4);
--    with a reply filter too: Emails + replies = none (t4 and t5 are on no channel, so email, but not review types).
SELECT pg_temp.expect('v2 Emails + replies', pg_temp.total(2, NULL, NULL, 'email', 'replies_all'), 0);
SELECT pg_temp.expect('v1 Emails + replies (the old rule)', pg_temp.total(1, NULL, NULL, 'email', 'replies_all'), 2);
SELECT pg_temp.expect('v2 LinkedIn + replies', pg_temp.total(2, NULL, NULL, 'linkedin', 'replies_all'), 2);

-- 3. Due bounds, from inclusive and before exclusive; no due date is outside any bound.
--    Overdue on 2026-10-19 (before midnight): t1. Today: t2 t3 t4 (10:00, 12:00, 08:00). From 10:00 exactly: t2 t3.
SELECT pg_temp.expect('v2 overdue', pg_temp.total(2, 'pending', NULL, NULL, NULL, NULL, '2026-10-19T00:00Z'), 1);
SELECT pg_temp.expect('v2 due today', pg_temp.total(2, 'pending', NULL, NULL, NULL, '2026-10-19T00:00Z', '2026-10-20T00:00Z'), 3);
SELECT pg_temp.expect('v2 from is inclusive', pg_temp.total(2, 'pending', NULL, NULL, NULL, '2026-10-19T10:00Z', '2026-10-20T00:00Z'), 2);
SELECT pg_temp.expect('v2 before is exclusive', pg_temp.total(2, NULL, NULL, NULL, NULL, '2026-10-20T00:00Z', '2026-10-20T09:00Z'), 0);
SELECT pg_temp.expect('v2 due + LinkedIn pill', pg_temp.total(2, 'pending', NULL, 'linkedin', NULL, '2026-10-19T00:00Z', '2026-10-20T00:00Z'), 2);

-- The groups' shape is v1's: status x bucket x channel. Pending LinkedIn review rows = t2 t3 t9.
DO $$ BEGIN
  IF (SELECT tasks FROM public.task_stats_counts_v2('org_a', 'pending') WHERE bucket = 'review' AND channel = 'linkedin') <> 3 THEN
    RAISE EXCEPTION 'the pending LinkedIn review group is not 3';
  END IF;
  IF (SELECT tasks FROM public.task_stats_counts_v2('org_a', 'pending') WHERE bucket = 'other') <> 1 THEN
    RAISE EXCEPTION 'manual outreach without a pill is not in the other bucket';
  END IF;
END $$;

-- Grants: service_role only (Supabase grants new public functions to anon and authenticated by default).
DO $$ BEGIN
  IF has_function_privilege('anon', 'public.task_stats_counts_v2(text, text, text, text, uuid, uuid, uuid, boolean, text, text, text, timestamptz, timestamptz)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.task_stats_counts_v2(text, text, text, text, uuid, uuid, uuid, boolean, text, text, text, timestamptz, timestamptz)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.task_stats_counts_v2(text, text, text, text, uuid, uuid, uuid, boolean, text, text, text, timestamptz, timestamptz)', 'EXECUTE') THEN
    RAISE EXCEPTION 'task_stats_counts_v2 grants are wrong';
  END IF;
  IF (SELECT provolatile FROM pg_proc WHERE proname = 'task_stats_counts_v2') <> 's' THEN RAISE EXCEPTION 'v2 is not STABLE'; END IF;
END $$;
