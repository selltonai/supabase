-- KAN-322 FR-A11g: dashboard_people_reply_rollup_v2 = v1's email and LinkedIn rows, plus 'all' (one person once
-- across both channels). Runs after the v1 contract (its fixtures stay). Disposable database only.
-- Window [2026-09-24, 2026-10-01).

-- org_y, my play and my LinkedIn seat:
--   Y1 emailed 09-25 and replied by email 09-29; also on LinkedIn (thread linked to Y1): out 09-26, in 09-27.
--   Y2 emailed 09-26, no reply.
--   Y3 an unlinked LinkedIn counterpart: out 09-25, in 09-26 (a person of its own).
--   Y4 emailed 09-27; replied on LinkedIn 09-28 (no LinkedIn outreach in the window).
--   Y5 replied on LinkedIn 09-25, then emailed 09-27 (the reply came before any outreach).
--   Y6 emailed 09-25, replied by email 09-26; LinkedIn outreach later (09-28): the FIRST outreach is the email.
--   Y7 replied on LinkedIn 09-25, emailed 09-26, replied by email 09-28: the LAST reply follows the first outreach.
--   Y8 emailed 09-25; its LinkedIn thread is NOT linked to the contact (counterpart urn:y8), but the contact carries that
--      LinkedIn id: out 09-26, in 09-27 -> one person in 'all'. A contact of another workspace with Y3's LinkedIn id
--      does not make Y3 one of its people.
INSERT INTO public.contacts (id, organization_id, linkedin_provider_id) VALUES
  ('00000000-0000-0000-0000-0000000000b8', 'org_y', 'urn:y8'),
  -- Another workspace's contact with Y3's LinkedIn id. Its id is Y2's (emailed in org_y, not in org_y's contacts), so
  -- matching across workspaces would merge Y3 into Y2 and show.
  ('00000000-0000-0000-0000-0000000000b2', 'org_a', 'urn:y3');
INSERT INTO public.campaigns VALUES ('00000000-0000-0000-0000-0000000000f1', 'org_y', 'u_me');
INSERT INTO public.campaign_emails (organization_id, campaign_id, contact_id, status, sent_at) VALUES
  ('org_y', '00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000b1', 'sent', '2026-09-25'),
  ('org_y', '00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000b2', 'sent', '2026-09-26'),
  ('org_y', '00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000b4', 'sent', '2026-09-27'),
  ('org_y', '00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000b5', 'sent', '2026-09-27'),
  ('org_y', '00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000b6', 'sent', '2026-09-25'),
  ('org_y', '00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000b7', 'sent', '2026-09-26'),
  ('org_y', '00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-0000000000b8', 'sent', '2026-09-25');
INSERT INTO public.email_reply_events (organization_id, contact_id, campaign_id, received_at) VALUES
  ('org_y', '00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000000f1', '2026-09-29'),
  ('org_y', '00000000-0000-0000-0000-0000000000b6', '00000000-0000-0000-0000-0000000000f1', '2026-09-26'),
  ('org_y', '00000000-0000-0000-0000-0000000000b7', '00000000-0000-0000-0000-0000000000f1', '2026-09-28');
INSERT INTO public.linkedin_threads (organization_id, owner_user_id, contact_id, unipile_chat_id, counterpart_provider_id, thread_origin) VALUES
  ('org_y', 'u_me', '00000000-0000-0000-0000-0000000000b1', 'y1', 'urn:y1', 'sellton_outbound'),
  ('org_y', 'u_me', NULL, 'y3', 'urn:y3', 'sellton_outbound'),
  ('org_y', 'u_me', '00000000-0000-0000-0000-0000000000b4', 'y4', 'urn:y4', 'campaign_inbound'),
  ('org_y', 'u_me', '00000000-0000-0000-0000-0000000000b5', 'y5', 'urn:y5', 'campaign_inbound'),
  ('org_y', 'u_me', '00000000-0000-0000-0000-0000000000b6', 'y6', 'urn:y6', 'sellton_outbound'),
  ('org_y', 'u_me', '00000000-0000-0000-0000-0000000000b7', 'y7', 'urn:y7', 'campaign_inbound'),
  ('org_y', 'u_me', NULL, 'y8', 'urn:y8', 'sellton_outbound');
INSERT INTO public.linkedin_messages (organization_id, unipile_chat_id, direction, occurred_at) VALUES
  ('org_y', 'y1', 'outbound', '2026-09-26'), ('org_y', 'y1', 'inbound', '2026-09-27'),
  ('org_y', 'y3', 'outbound', '2026-09-25'), ('org_y', 'y3', 'inbound', '2026-09-26'),
  ('org_y', 'y4', 'inbound', '2026-09-28'),
  ('org_y', 'y5', 'inbound', '2026-09-25'),
  ('org_y', 'y6', 'outbound', '2026-09-28'),
  ('org_y', 'y7', 'inbound', '2026-09-25'),
  ('org_y', 'y8', 'outbound', '2026-09-26'), ('org_y', 'y8', 'inbound', '2026-09-27');

DO $$
DECLARE r record; v1 text; v2 text; args record;
BEGIN
  -- 1. v2's email and LinkedIn rows equal v1's, for every workspace, window and scope the contracts use.
  FOR args IN
    SELECT * FROM (VALUES
      ('org_a', '2026-09-24'::timestamptz, '2026-10-01'::timestamptz, NULL::text),
      ('org_a', '2026-09-24', '2026-10-01', 'u_me'),
      ('org_a', '2026-08-01', '2026-09-24', NULL),
      ('org_b', '2026-09-24', '2026-10-01', NULL),
      ('org_y', '2026-09-24', '2026-10-01', NULL),
      ('org_y', '2026-09-24', '2026-10-01', 'u_me'),
      ('org_y', '2026-09-24', '2026-10-01', 'u_other')) t(org, s, e, u)
  LOOP
    SELECT string_agg(format('%s:%s/%s/%s', channel, people_reached, people_replied, reached_and_replied), ' ' ORDER BY channel)
      INTO v1 FROM public.dashboard_people_reply_rollup_v1(args.org, args.s, args.e, args.u);
    SELECT string_agg(format('%s:%s/%s/%s', channel, people_reached, people_replied, reached_and_replied), ' ' ORDER BY channel)
      INTO v2 FROM public.dashboard_people_reply_rollup_v2(args.org, args.s, args.e, args.u) WHERE channel <> 'all';
    IF v1 IS DISTINCT FROM v2 THEN
      RAISE EXCEPTION 'v2 channel rows differ from v1 for %: v1 % / v2 %', args, v1, v2;
    END IF;
  END LOOP;

  -- 2. org_y by channel (as v1): email reached Y1, Y2, Y4, Y5, Y6, Y7, Y8 = 7, replied Y1, Y6, Y7 = 3, in the rate 3;
  --    LinkedIn reached Y1, Y3, Y6, li:urn:y8 = 4, replied Y1, Y3, Y4, Y5, Y7, li:urn:y8 = 6, in the rate Y1, Y3, y8 = 3.
  SELECT string_agg(format('%s:%s/%s/%s', channel, people_reached, people_replied, reached_and_replied), ' ' ORDER BY channel)
    INTO v2 FROM public.dashboard_people_reply_rollup_v2('org_y', '2026-09-24', '2026-10-01');
  -- 3. all: reached Y1 to Y8 = 8 (not 11: Y1, Y6 and Y8 are one person each); replied Y1, Y3, Y4, Y5, Y6, Y7, Y8 = 7
  --    (not 9); in the rate Y1, Y3, Y4 (its LinkedIn reply follows its email), Y6 (its first outreach is the email),
  --    Y7 (its last reply follows its email), Y8 (matched by its LinkedIn id) = 6; Y5's only reply came before any
  --    outreach. Y3 stays its own person (the contact with its LinkedIn id is another workspace's).
  IF v2 IS DISTINCT FROM 'all:8/7/6 email:7/3/3 linkedin:4/6/3' THEN
    RAISE EXCEPTION 'org_y: got %', v2;
  END IF;

  -- 4. org_a (v1's fixtures): its email and LinkedIn people are different contacts, so all = the sums, except the
  --    LinkedIn people keyed 'li:' never match an email contact. The rate's part never passes reached.
  FOR r IN SELECT * FROM public.dashboard_people_reply_rollup_v2('org_a', '2026-09-24', '2026-10-01') LOOP
    IF r.reached_and_replied > r.people_reached THEN
      RAISE EXCEPTION 'rate part above reached for %', r.channel;
    END IF;
  END LOOP;
  SELECT string_agg(format('%s:%s/%s/%s', channel, people_reached, people_replied, reached_and_replied), ' ' ORDER BY channel)
    INTO v2 FROM public.dashboard_people_reply_rollup_v2('org_a', '2026-09-24', '2026-10-01');
  IF split_part(v2, ' ', 1) IS DISTINCT FROM (
       SELECT format('all:%s/%s/%s', sum(people_reached), sum(people_replied), sum(reached_and_replied))
         FROM public.dashboard_people_reply_rollup_v1('org_a', '2026-09-24', '2026-10-01')) THEN
    RAISE EXCEPTION 'org_a: all should equal the sums (no shared person): %', v2;
  END IF;

  -- 5. A colleague's scope sees none of org_y (my play, my seat): three rows of zeros.
  SELECT string_agg(format('%s:%s/%s/%s', channel, people_reached, people_replied, reached_and_replied), ' ' ORDER BY channel)
    INTO v2 FROM public.dashboard_people_reply_rollup_v2('org_y', '2026-09-24', '2026-10-01', 'u_other');
  IF v2 IS DISTINCT FROM 'all:0/0/0 email:0/0/0 linkedin:0/0/0' THEN
    RAISE EXCEPTION 'org_y for a colleague: got %', v2;
  END IF;

  IF has_function_privilege('anon', 'public.dashboard_people_reply_rollup_v2(text, timestamptz, timestamptz, text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.dashboard_people_reply_rollup_v2(text, timestamptz, timestamptz, text)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.dashboard_people_reply_rollup_v2(text, timestamptz, timestamptz, text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'grants: anon or authenticated can call v2, or service_role cannot';
  END IF;
  RAISE NOTICE 'dashboard_people_reply_rollup_v2 contract: ok';
END $$;
