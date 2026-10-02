-- KAN-322 FR-A11 (D9): dashboard_people_reply_rollup_v1 counts people, not messages. Disposable database only.
-- Window [2026-09-24, 2026-10-01). Expected values are worked out by hand next to each fixture.
INSERT INTO public.campaigns VALUES
  ('00000000-0000-0000-0000-0000000000c1', 'org_a', 'u_me'),
  ('00000000-0000-0000-0000-0000000000c2', 'org_a', 'u_other'),
  ('00000000-0000-0000-0000-0000000000c3', 'org_b', 'u_me');

-- Email. A: three sends (two emails, one task), one reply after -> reached once, replied, in the rate.
INSERT INTO public.campaign_emails (organization_id, campaign_id, contact_id, status, sent_at) VALUES
  ('org_a', '00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-00000000000a', 'sent', '2026-09-25'),
  ('org_a', '00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-00000000000a', 'sent', '2026-09-27');
INSERT INTO public.tasks (organization_id, task_type, send_status, sent_at, campaign_id, contact_id) VALUES
  ('org_a', 'review_draft', 'sent_success', '2026-09-26', '00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-00000000000a');
INSERT INTO public.email_reply_events (organization_id, contact_id, campaign_id, received_at) VALUES
  ('org_a', '00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-0000000000c1', '2026-09-28'),
  ('org_a', '00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-0000000000c1', '2026-09-29');
-- B: a colleague's campaign (task send), replied after -> team only.
INSERT INTO public.tasks (organization_id, task_type, send_status, sent_at, campaign_id, contact_id) VALUES
  ('org_a', 'review_draft', 'sent_success', '2026-09-25', '00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-00000000000b');
INSERT INTO public.email_reply_events (organization_id, contact_id, campaign_id, received_at) VALUES
  ('org_a', '00000000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-0000000000c2', '2026-09-26');
-- C: only a reply-type email -> not outreach, not reached.
INSERT INTO public.campaign_emails (organization_id, campaign_id, contact_id, status, sent_at, metadata) VALUES
  ('org_a', '00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-00000000000c', 'sent', '2026-09-25', '{"email_type":"Reply"}');
-- D: reached before the window, replied inside it -> counts as a reply, not in the rate.
INSERT INTO public.campaign_emails (organization_id, campaign_id, contact_id, status, sent_at) VALUES
  ('org_a', '00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-00000000000d', 'sent', '2026-09-10');
INSERT INTO public.email_reply_events (organization_id, contact_id, campaign_id, received_at) VALUES
  ('org_a', '00000000-0000-0000-0000-00000000000d', '00000000-0000-0000-0000-0000000000c1', '2026-09-25');
-- E: reached in the window; its only reply came before the window -> reached, no reply.
INSERT INTO public.campaign_emails (organization_id, campaign_id, contact_id, status, sent_at) VALUES
  ('org_a', '00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-00000000000e', 'delivered', '2026-09-26');
INSERT INTO public.email_reply_events (organization_id, contact_id, campaign_id, received_at) VALUES
  ('org_a', '00000000-0000-0000-0000-00000000000e', '00000000-0000-0000-0000-0000000000c1', '2026-09-01');
-- F: reached; a reply event without a campaign -> not a countable reply.
INSERT INTO public.campaign_emails (organization_id, campaign_id, contact_id, status, sent_at) VALUES
  ('org_a', '00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-00000000000f', 'sent', '2026-09-27');
INSERT INTO public.email_reply_events (organization_id, contact_id, campaign_id, received_at) VALUES
  ('org_a', '00000000-0000-0000-0000-00000000000f', NULL, '2026-09-28');
-- H: wrote to us first inside the window, then we sent -> reached and a reply, but not in the rate.
INSERT INTO public.email_reply_events (organization_id, contact_id, campaign_id, received_at) VALUES
  ('org_a', '00000000-0000-0000-0000-000000000012', '00000000-0000-0000-0000-0000000000c1', '2026-09-26');
INSERT INTO public.campaign_emails (organization_id, campaign_id, contact_id, status, sent_at) VALUES
  ('org_a', '00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-000000000012', 'sent', '2026-09-28');
-- G: a draft never sent -> not reached. Other org: never counted.
INSERT INTO public.campaign_emails (organization_id, campaign_id, contact_id, status, sent_at) VALUES
  ('org_a', '00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-000000000010', 'draft', NULL),
  ('org_b', '00000000-0000-0000-0000-0000000000c3', '00000000-0000-0000-0000-000000000011', 'sent', '2026-09-25');

-- LinkedIn. P1 on two of my threads: two messages out, three replies -> one person, reached, replied, in the rate.
INSERT INTO public.linkedin_threads (organization_id, owner_user_id, contact_id, unipile_chat_id, counterpart_provider_id, thread_origin) VALUES
  ('org_a', 'u_me', '00000000-0000-0000-0000-0000000000a1', 'chat1', 'urn:1', 'sellton_outbound'),
  ('org_a', 'u_me', '00000000-0000-0000-0000-0000000000a1', 'chat4', 'urn:1', 'sellton_outbound'),
  ('org_a', 'u_other', NULL, 'chat2', 'urn:2', 'campaign_inbound'),
  ('org_a', 'u_me', NULL, 'chat3', 'urn:3', 'personal'),
  ('org_a', 'u_me', NULL, 'chat5', 'urn:5', 'sellton_outbound'),
  ('org_b', 'u_me', NULL, 'chat9', 'urn:9', 'sellton_outbound');
INSERT INTO public.linkedin_messages (organization_id, unipile_chat_id, direction, occurred_at) VALUES
  ('org_a', 'chat1', 'outbound', '2026-09-25'), ('org_a', 'chat1', 'outbound', '2026-09-26'),
  ('org_a', 'chat1', 'inbound', '2026-09-26 12:00'), ('org_a', 'chat1', 'inbound', '2026-09-27'), ('org_a', 'chat1', 'inbound', '2026-09-28'),
  ('org_a', 'chat4', 'outbound', '2026-09-29'),
  -- urn:2 wrote first, we answered: reached, replied in the window, but not after our first message.
  ('org_a', 'chat2', 'inbound', '2026-09-25'), ('org_a', 'chat2', 'outbound', '2026-09-26'),
  -- A personal thread never counts.
  ('org_a', 'chat3', 'outbound', '2026-09-25'), ('org_a', 'chat3', 'inbound', '2026-09-26'),
  -- urn:5 messaged before the window, replied inside it: a reply, not reached in the window.
  ('org_a', 'chat5', 'outbound', '2026-09-01'), ('org_a', 'chat5', 'inbound', '2026-09-27'),
  ('org_b', 'chat9', 'outbound', '2026-09-25'), ('org_b', 'chat9', 'inbound', '2026-09-26');

DO $$
DECLARE r record;
BEGIN
  -- Whole team.
  SELECT * INTO r FROM public.dashboard_people_reply_rollup_v1('org_a', '2026-09-24', '2026-10-01') WHERE channel = 'email';
  IF (r.people_reached, r.people_replied, r.reached_and_replied) IS DISTINCT FROM (5::bigint, 4::bigint, 2::bigint) THEN
    RAISE EXCEPTION 'email team: got % % %, want 5 4 2 (A,B,E,F,H / A,B,D,H / A,B)', r.people_reached, r.people_replied, r.reached_and_replied;
  END IF;
  SELECT * INTO r FROM public.dashboard_people_reply_rollup_v1('org_a', '2026-09-24', '2026-10-01') WHERE channel = 'linkedin';
  IF (r.people_reached, r.people_replied, r.reached_and_replied) IS DISTINCT FROM (2::bigint, 3::bigint, 1::bigint) THEN
    RAISE EXCEPTION 'linkedin team: got % % %, want 2 3 1 (P1,urn2 / P1,urn2,urn5 / P1)', r.people_reached, r.people_replied, r.reached_and_replied;
  END IF;
  -- Just me.
  SELECT * INTO r FROM public.dashboard_people_reply_rollup_v1('org_a', '2026-09-24', '2026-10-01', 'u_me') WHERE channel = 'email';
  IF (r.people_reached, r.people_replied, r.reached_and_replied) IS DISTINCT FROM (4::bigint, 3::bigint, 1::bigint) THEN
    RAISE EXCEPTION 'email mine: got % % %, want 4 3 1 (A,E,F,H / A,D,H / A)', r.people_reached, r.people_replied, r.reached_and_replied;
  END IF;
  SELECT * INTO r FROM public.dashboard_people_reply_rollup_v1('org_a', '2026-09-24', '2026-10-01', 'u_me') WHERE channel = 'linkedin';
  IF (r.people_reached, r.people_replied, r.reached_and_replied) IS DISTINCT FROM (1::bigint, 2::bigint, 1::bigint) THEN
    RAISE EXCEPTION 'linkedin mine: got % % %, want 1 2 1 (P1 / P1,urn5 / P1)', r.people_reached, r.people_replied, r.reached_and_replied;
  END IF;
  -- Exactly two rows, and an empty org is two zero rows (never missing).
  IF (SELECT count(*) FROM public.dashboard_people_reply_rollup_v1('org_none', '2026-09-24', '2026-10-01')) <> 2 THEN
    RAISE EXCEPTION 'expected two rows for an empty org';
  END IF;
  IF EXISTS (SELECT 1 FROM public.dashboard_people_reply_rollup_v1('org_none', '2026-09-24', '2026-10-01')
             WHERE people_reached <> 0 OR people_replied <> 0 OR reached_and_replied <> 0) THEN
    RAISE EXCEPTION 'empty org must be zeros';
  END IF;
  -- Only service_role may call it.
  IF has_function_privilege('authenticated', 'public.dashboard_people_reply_rollup_v1(text, timestamptz, timestamptz, text)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.dashboard_people_reply_rollup_v1(text, timestamptz, timestamptz, text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'grants wrong';
  END IF;
END $$;
SELECT 'dashboard_people_reply_rollup_v1 contract passed' AS result;
