-- KAN-322 FR-A11b (D15): campaign_channel_stats_v1 per-campaign numbers by person. Disposable database only.
-- s1 = 5000..01 (busy), s2 = 5000..02 (no activity), s3 = 5000..03 (another organization).
INSERT INTO public.campaigns VALUES
  ('00000000-0000-0000-0000-000000005001', 'org_s', 'u_s'),
  ('00000000-0000-0000-0000-000000005002', 'org_s', 'u_s'),
  ('00000000-0000-0000-0000-000000005003', 'org_x', 'u_x'),
  ('00000000-0000-0000-0000-000000005004', 'org_s', 'u_s');

-- Email on s1. K: one email recorded twice (campaign_emails and its task, same message id) plus a second email.
INSERT INTO public.campaign_emails (organization_id, campaign_id, contact_id, status, sent_at, message_id) VALUES
  ('org_s', '00000000-0000-0000-0000-000000005001', '00000000-0000-0000-0000-00000000500a', 'sent', '2026-09-20', 'm1'),
  ('org_s', '00000000-0000-0000-0000-000000005001', '00000000-0000-0000-0000-00000000500a', 'opened', '2026-09-22', 'm2');
INSERT INTO public.tasks (organization_id, task_type, send_status, sent_at, campaign_id, contact_id, email_id) VALUES
  ('org_s', 'review_draft', 'sent_success', '2026-09-20', '00000000-0000-0000-0000-000000005001', '00000000-0000-0000-0000-00000000500a', 'm1'),
  -- L: one email sent from a task only.
  ('org_s', 'review_draft', 'sent_success', '2026-09-21', '00000000-0000-0000-0000-000000005001', '00000000-0000-0000-0000-00000000500b', 'm3');
-- Not outreach: a reply-type email to L, and an unsent draft to M.
INSERT INTO public.campaign_emails (organization_id, campaign_id, contact_id, status, sent_at, message_id, metadata) VALUES
  ('org_s', '00000000-0000-0000-0000-000000005001', '00000000-0000-0000-0000-00000000500b', 'sent', '2026-09-23', 'm4', '{"type":"meeting_response"}'),
  ('org_s', '00000000-0000-0000-0000-000000005001', '00000000-0000-0000-0000-00000000500c', 'draft', NULL, NULL, '{}');
-- Replies on s1: K twice (one person), N (a reply on the campaign), and one with no campaign (not counted).
INSERT INTO public.email_reply_events (organization_id, contact_id, campaign_id, received_at) VALUES
  ('org_s', '00000000-0000-0000-0000-00000000500a', '00000000-0000-0000-0000-000000005001', '2026-09-24'),
  ('org_s', '00000000-0000-0000-0000-00000000500a', '00000000-0000-0000-0000-000000005001', '2026-09-25'),
  ('org_s', '00000000-0000-0000-0000-00000000500d', '00000000-0000-0000-0000-000000005001', '2026-09-25'),
  ('org_s', '00000000-0000-0000-0000-00000000500b', NULL, '2026-09-25');

-- LinkedIn on s1. Invites: urn:k twice (a retry), urn:m, a failed one to urn:l; messages: urn:k twice.
INSERT INTO public.linkedin_action_log (organization_id, campaign_id, action_type, success, counterpart_provider_id, recipient_provider_id) VALUES
  ('org_s', '00000000-0000-0000-0000-000000005001', 'invitation', true, 'urn:k', 'urn:k'),
  ('org_s', '00000000-0000-0000-0000-000000005001', 'invitation', true, NULL, 'urn:k'),
  ('org_s', '00000000-0000-0000-0000-000000005001', 'invitation', true, 'urn:m', 'urn:m'),
  ('org_s', '00000000-0000-0000-0000-000000005001', 'invitation', false, 'urn:l', 'urn:l'),
  ('org_s', '00000000-0000-0000-0000-000000005001', 'message', true, 'urn:k', 'urn:k'),
  ('org_s', '00000000-0000-0000-0000-000000005001', 'message', true, 'urn:k', 'urn:k'),
  ('org_s', '00000000-0000-0000-0000-000000005001', 'profile_view', true, 'urn:z', 'urn:z'),
  ('org_x', '00000000-0000-0000-0000-000000005003', 'invitation', true, 'urn:x', 'urn:x');
-- Accepted: K and M connected now, L only invited.
INSERT INTO public.campaign_contacts (campaign_id, contact_id, organization_id, linkedin_account_id, relation_state, created_at) VALUES
  ('00000000-0000-0000-0000-000000005001', '00000000-0000-0000-0000-00000000500a', 'org_s', '00000000-0000-0000-0000-0000000a0001', 'connected', '2026-09-01'),
  ('00000000-0000-0000-0000-000000005001', '00000000-0000-0000-0000-00000000500b', 'org_s', '00000000-0000-0000-0000-0000000a0001', 'invited', '2026-09-01'),
  ('00000000-0000-0000-0000-000000005001', '00000000-0000-0000-0000-00000000500c', 'org_s', '00000000-0000-0000-0000-0000000a0001', 'connected', '2026-09-01'),
  -- R re-enrolled on 09-25; its only reply (an untagged thread) is from 09-10, before -> not a reply for s1.
  ('00000000-0000-0000-0000-000000005001', '00000000-0000-0000-0000-00000000500f', 'org_s', '00000000-0000-0000-0000-0000000a0001', 'connected', '2026-09-25');
-- Threads: K's carries the campaign (two replies, one person); M's is linked through its campaign contact on the same
-- account; a personal (unrelated_inbound) thread never counts even with the campaign on it; L on another LinkedIn
-- account is not this campaign's thread.
INSERT INTO public.linkedin_threads (organization_id, owner_user_id, contact_id, campaign_id, unipile_chat_id, counterpart_provider_id, thread_origin, linkedin_account_id) VALUES
  ('org_s', 'u_s', '00000000-0000-0000-0000-00000000500a', '00000000-0000-0000-0000-000000005001', 'sk', 'urn:k', 'sellton_outbound', '00000000-0000-0000-0000-0000000a0001'),
  ('org_s', 'u_s', '00000000-0000-0000-0000-00000000500c', NULL, 'sm', 'urn:m', 'campaign_inbound', '00000000-0000-0000-0000-0000000a0001'),
  ('org_s', 'u_s', '00000000-0000-0000-0000-00000000500e', '00000000-0000-0000-0000-000000005001', 'sp', 'urn:e', 'unrelated_inbound', '00000000-0000-0000-0000-0000000a0001'),
  ('org_s', 'u_s', '00000000-0000-0000-0000-00000000500b', NULL, 'sq', 'urn:l', 'sellton_outbound', '00000000-0000-0000-0000-0000000a0002'),
  ('org_s', 'u_s', '00000000-0000-0000-0000-00000000500b', '00000000-0000-0000-0000-000000005001', 'sl', 'urn:l', 'sellton_outbound', '00000000-0000-0000-0000-0000000a0001'),
  ('org_s', 'u_s', '00000000-0000-0000-0000-00000000500f', NULL, 'sr', 'urn:r', 'sellton_outbound', '00000000-0000-0000-0000-0000000a0001'),
  -- L replied on a thread tagged with s4: a reply for s4 only, although L is also enrolled on s1 (same account).
  ('org_s', 'u_s', '00000000-0000-0000-0000-00000000500b', '00000000-0000-0000-0000-000000005004', 's4', 'urn:l', 'sellton_outbound', '00000000-0000-0000-0000-0000000a0001');
INSERT INTO public.linkedin_messages (organization_id, unipile_chat_id, direction, occurred_at) VALUES
  ('org_s', 'sk', 'outbound', '2026-09-20'), ('org_s', 'sk', 'inbound', '2026-09-21'), ('org_s', 'sk', 'inbound', '2026-09-22'),
  ('org_s', 'sm', 'inbound', '2026-09-21'),
  ('org_s', 'sp', 'inbound', '2026-09-21'),
  ('org_s', 'sq', 'inbound', '2026-09-21'),
  ('org_s', 'sl', 'outbound', '2026-09-21'),
  ('org_s', 'sr', 'inbound', '2026-09-10'),
  ('org_s', 's4', 'inbound', '2026-09-22');

DO $$
DECLARE r record; n int;
BEGIN
  SELECT * INTO r FROM public.campaign_channel_stats_v1('org_s', ARRAY['00000000-0000-0000-0000-000000005001']::uuid[]);
  IF (r.email_sent, r.email_people_reached, r.email_people_replied) IS DISTINCT FROM (3::bigint, 2::bigint, 1::bigint) THEN
    RAISE EXCEPTION 'email: got % % %, want 3 2 1 (m1,m2,m3 / K,L / K; N was never reached)', r.email_sent, r.email_people_reached, r.email_people_replied;
  END IF;
  IF (r.linkedin_people_invited, r.linkedin_people_accepted, r.linkedin_people_messaged, r.linkedin_people_replied)
     IS DISTINCT FROM (2::bigint, 3::bigint, 1::bigint, 2::bigint) THEN
    RAISE EXCEPTION 'linkedin: got % % % %, want 2 3 1 2 (k,m / K,M,R / k / K,M)',
      r.linkedin_people_invited, r.linkedin_people_accepted, r.linkedin_people_messaged, r.linkedin_people_replied;
  END IF;
  -- An idle campaign is a row of zeros; another org's campaign and unknown ids are not returned.
  SELECT count(*) INTO n FROM public.campaign_channel_stats_v1('org_s', ARRAY[
    '00000000-0000-0000-0000-000000005001', '00000000-0000-0000-0000-000000005002',
    '00000000-0000-0000-0000-000000005003', '00000000-0000-0000-0000-00000000ffff']::uuid[]);
  IF n <> 2 THEN RAISE EXCEPTION 'expected 2 rows (s1, s2), got %', n; END IF;
  SELECT * INTO r FROM public.campaign_channel_stats_v1('org_s', ARRAY['00000000-0000-0000-0000-000000005002']::uuid[]);
  IF (r.email_sent, r.email_people_reached, r.email_people_replied, r.linkedin_people_invited, r.linkedin_people_accepted,
      r.linkedin_people_messaged, r.linkedin_people_replied) IS DISTINCT FROM (0::bigint, 0::bigint, 0::bigint, 0::bigint, 0::bigint, 0::bigint, 0::bigint) THEN
    RAISE EXCEPTION 'idle campaign must be zeros';
  END IF;
  SELECT * INTO r FROM public.campaign_channel_stats_v1('org_s', ARRAY['00000000-0000-0000-0000-000000005004']::uuid[]);
  IF r.linkedin_people_replied <> 1 THEN RAISE EXCEPTION 's4 tagged thread: got %, want 1 (L)', r.linkedin_people_replied; END IF;
  IF (SELECT count(*) FROM public.campaign_channel_stats_v1('org_s', ARRAY[]::uuid[])) <> 0 THEN
    RAISE EXCEPTION 'no ids, no rows';
  END IF;
  IF has_function_privilege('authenticated', 'public.campaign_channel_stats_v1(text, uuid[])', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.campaign_channel_stats_v1(text, uuid[])', 'EXECUTE') THEN
    RAISE EXCEPTION 'grants wrong';
  END IF;
END $$;
SELECT 'campaign_channel_stats_v1 contract passed' AS result;
