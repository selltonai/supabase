-- KAN-309 V2: migration 405's contract (the pinned supabase <-> modal contract for bump_verification_digest).
-- Run by tests/run-verification-digest-contract.sh on a disposable database, after the notifications migrations
-- (245, 244, 361, 376's type CHECK) and 405 applied twice.

-- Grants: service role only; SECURITY DEFINER with a fixed search_path.
DO $$
DECLARE
  sig constant text := 'public.bump_verification_digest(text, text, text, text, text, text, integer)';
BEGIN
  IF has_function_privilege('anon', sig, 'EXECUTE') OR has_function_privilege('authenticated', sig, 'EXECUTE') THEN
    RAISE EXCEPTION 'anon/authenticated can execute bump_verification_digest';
  END IF;
  IF has_function_privilege('anon', 'public.verification_digest_title(text, integer, text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.verification_digest_title(text, integer, text)', 'EXECUTE')
     OR has_function_privilege('service_role', 'public.verification_digest_title(text, integer, text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'the title helper is executable outside the definer';
  END IF;
  IF NOT has_function_privilege('service_role', sig, 'EXECUTE') THEN RAISE EXCEPTION 'service_role cannot execute'; END IF;
  IF NOT (SELECT prosecdef FROM pg_proc WHERE oid = sig::regprocedure) THEN RAISE EXCEPTION 'not SECURITY DEFINER'; END IF;
  IF NOT (SELECT proconfig @> ARRAY['search_path=public'] FROM pg_proc WHERE oid = sig::regprocedure) THEN
    RAISE EXCEPTION 'search_path is not pinned to public';
  END IF;
  IF (SELECT pg_get_function_result(sig::regprocedure)) <> 'uuid' THEN RAISE EXCEPTION 'does not return uuid'; END IF;
  IF (SELECT pg_get_function_arguments(sig::regprocedure)) <>
     'p_organization_id text, p_user_id text, p_campaign_id text, p_kind text, p_campaign_name text, p_action_url text, p_delta integer DEFAULT 1' THEN
    RAISE EXCEPTION 'argument names or default differ from the pinned contract: %', pg_get_function_arguments(sig::regprocedure);
  END IF;
END $$;

-- authenticated is refused even though Supabase's default privileges would have granted it.
BEGIN;
SET LOCAL ROLE authenticated;
DO $$ BEGIN
  PERFORM public.bump_verification_digest('org_a', 'user_1', 'camp_1', 'company', 'Q4', '/sellton?tab=tasks', 1);
  RAISE EXCEPTION 'authenticated could call bump_verification_digest';
EXCEPTION WHEN insufficient_privilege THEN NULL; END $$;
ROLLBACK;

-- Behaviour, as the service role (Modal's key).
SET ROLE service_role;
DO $$
DECLARE
  today constant text := to_char((now() AT TIME ZONE 'utc')::date, 'YYYY-MM-DD');
  first_id uuid;
  again_id uuid;
  other_id uuid;
  r public.notifications;
BEGIN
  -- First bump creates the row with the pinned fields.
  first_id := public.bump_verification_digest('org_a', 'user_1', 'camp_1', 'company', 'Q4 Outreach', '/sellton?tab=tasks&campaignId=camp_1');
  SELECT * INTO r FROM public.notifications WHERE id = first_id;
  IF r.type <> 'task_assigned' OR r.channels <> ARRAY['in_app']::text[] OR r.priority <> 'normal'
     OR r.entity_type <> 'campaign' OR r.entity_id <> 'camp_1' OR r.organization_id <> 'org_a' OR r.user_id <> 'user_1'
     OR r.action_url <> '/sellton?tab=tasks&campaignId=camp_1' OR r.read OR r.dismissed THEN
    RAISE EXCEPTION 'first bump wrote the wrong fields: %', row_to_json(r);
  END IF;
  IF r.dedup_key <> 'verification_digest:company:camp_1:' || today THEN RAISE EXCEPTION 'dedup_key %', r.dedup_key; END IF;
  IF r.metadata <> jsonb_build_object('kind', 'verification_digest', 'verification_kind', 'company', 'campaign_id', 'camp_1',
                                      'count', 1, 'organization_id', 'org_a') THEN
    RAISE EXCEPTION 'metadata %', r.metadata;
  END IF;
  IF r.title <> '1 company from Q4 Outreach is ready to verify' THEN RAISE EXCEPTION 'title %', r.title; END IF;
  IF r.body IS NULL OR r.body = '' THEN RAISE EXCEPTION 'empty body'; END IF;

  -- The person reads and dismisses it; it is old. A bump of 2 updates the same row in place and resurfaces it.
  UPDATE public.notifications SET read = true, read_at = now(), dismissed = true, created_at = '2020-01-01' WHERE id = first_id;
  again_id := public.bump_verification_digest('org_a', 'user_1', 'camp_1', 'company', 'Q4 Outreach', '/sellton?tab=tasks&campaignId=camp_1', 2);
  IF again_id <> first_id THEN RAISE EXCEPTION 'a bump created a second row'; END IF;
  SELECT * INTO r FROM public.notifications WHERE id = first_id;
  IF (r.metadata->>'count')::int <> 3 THEN RAISE EXCEPTION 'count % after 1 + 2', r.metadata->>'count'; END IF;
  IF r.title <> '3 companies from Q4 Outreach are ready to verify' THEN RAISE EXCEPTION 'title after bump %', r.title; END IF;
  IF r.read OR r.read_at IS NOT NULL OR r.dismissed OR r.created_at < '2021-01-01' THEN
    RAISE EXCEPTION 'the bump did not resurface the row: %', row_to_json(r);
  END IF;
  IF r.metadata->>'kind' <> 'verification_digest' OR r.metadata->>'organization_id' <> 'org_a' THEN
    RAISE EXCEPTION 'the bump lost metadata keys: %', r.metadata;
  END IF;

  -- A count the function cannot read counts as 0 (never a cast error).
  UPDATE public.notifications SET metadata = metadata || '{"count": "x"}' WHERE id = first_id;
  PERFORM public.bump_verification_digest('org_a', 'user_1', 'camp_1', 'company', 'Q4 Outreach', NULL);
  SELECT * INTO r FROM public.notifications WHERE id = first_id;
  IF (r.metadata->>'count')::int <> 1 OR r.title <> '1 company from Q4 Outreach is ready to verify' THEN
    RAISE EXCEPTION 'unreadable count: % / %', r.metadata->>'count', r.title;
  END IF;

  -- Contacts are a separate digest; no campaign name reads "your campaign" (null or blank).
  other_id := public.bump_verification_digest('org_a', 'user_1', 'camp_1', 'contact', NULL, '/sellton?tab=tasks');
  IF other_id = first_id THEN RAISE EXCEPTION 'contact and company digests share a row'; END IF;
  SELECT * INTO r FROM public.notifications WHERE id = other_id;
  IF r.title <> '1 contact from your campaign is ready to verify' OR r.dedup_key <> 'verification_digest:contact:camp_1:' || today
     OR r.metadata->>'verification_kind' <> 'contact' THEN
    RAISE EXCEPTION 'contact digest: % / % / %', r.title, r.dedup_key, r.metadata;
  END IF;
  PERFORM public.bump_verification_digest('org_a', 'user_1', 'camp_1', 'contact', '   ', '/sellton?tab=tasks', 4);
  SELECT * INTO r FROM public.notifications WHERE id = other_id;
  IF r.title <> '5 contacts from your campaign are ready to verify' THEN RAISE EXCEPTION 'blank name: %', r.title; END IF;

  -- Another person, or another campaign, gets their own row.
  IF public.bump_verification_digest('org_a', 'user_2', 'camp_1', 'company', 'Q4 Outreach', NULL) = first_id
     OR public.bump_verification_digest('org_a', 'user_1', 'camp_2', 'company', 'Other', NULL) = first_id THEN
    RAISE EXCEPTION 'a different person or campaign bumped the same row';
  END IF;

  -- Yesterday's digest is not bumped: today starts a new row.
  UPDATE public.notifications SET dedup_key = 'verification_digest:company:camp_1:2000-01-01' WHERE id = first_id;
  again_id := public.bump_verification_digest('org_a', 'user_1', 'camp_1', 'company', 'Q4 Outreach', NULL);
  IF again_id = first_id THEN RAISE EXCEPTION 'an old day''s digest was bumped'; END IF;
  IF (SELECT metadata->>'count' FROM public.notifications WHERE id = first_id) <> '1' THEN RAISE EXCEPTION 'the old digest changed'; END IF;

  -- Notifications without a dedup key are never touched.
  INSERT INTO public.notifications (organization_id, user_id, type, title) VALUES ('org_a', 'user_1', 'task_assigned', 'Verify Acme');
  PERFORM public.bump_verification_digest('org_a', 'user_1', 'camp_1', 'company', 'Q4 Outreach', NULL);
  IF (SELECT count(*) FROM public.notifications WHERE title = 'Verify Acme') <> 1 THEN RAISE EXCEPTION 'a plain notification was touched'; END IF;

  -- Rows: camp_1 company (old day + today), camp_1 contact, user_2 camp_1, user_1 camp_2, the plain one.
  IF (SELECT count(*) FROM public.notifications) <> 6 THEN
    RAISE EXCEPTION 'expected 6 notifications, have %', (SELECT count(*) FROM public.notifications);
  END IF;
END $$;

-- Bad input fails loud (22023); an unknown user or organization fails on the 245 foreign keys.
DO $$
BEGIN
  BEGIN PERFORM public.bump_verification_digest('org_a', 'user_1', 'camp_1', 'deal', 'Q4', NULL);
    RAISE EXCEPTION 'an unknown kind was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN PERFORM public.bump_verification_digest('org_a', 'user_1', 'camp_1', 'company', 'Q4', NULL, 0);
    RAISE EXCEPTION 'a delta of 0 was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN PERFORM public.bump_verification_digest('org_a', 'user_1', 'camp_1', 'company', 'Q4', NULL, NULL);
    RAISE EXCEPTION 'a null delta was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN PERFORM public.bump_verification_digest('org_a', 'user_1', ' ', 'company', 'Q4', NULL);
    RAISE EXCEPTION 'a blank campaign was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN PERFORM public.bump_verification_digest(NULL, 'user_1', 'camp_1', 'company', 'Q4', NULL);
    RAISE EXCEPTION 'a null organization was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN PERFORM public.bump_verification_digest('org_a', 'user_unknown', 'camp_1', 'company', 'Q4', NULL);
    RAISE EXCEPTION 'an unknown user was accepted';
  EXCEPTION WHEN foreign_key_violation THEN NULL; END;
  BEGIN PERFORM public.bump_verification_digest('org_unknown', 'user_1', 'camp_9', 'company', 'Q4', NULL);
    RAISE EXCEPTION 'an unknown organization was accepted';
  EXCEPTION WHEN foreign_key_violation THEN NULL; END;
END $$;
RESET ROLE;

-- The rollback removes both functions and keeps the rows.
BEGIN;
\ir ../migrations/next-release/rollback/405_bump-verification-digest.rollback.sql
DO $$ BEGIN
  IF to_regprocedure('public.bump_verification_digest(text, text, text, text, text, text, integer)') IS NOT NULL
     OR to_regprocedure('public.verification_digest_title(text, integer, text)') IS NOT NULL THEN
    RAISE EXCEPTION 'the 405 rollback left a function behind';
  END IF;
  IF (SELECT count(*) FROM public.notifications) <> 6 THEN RAISE EXCEPTION 'the rollback touched notifications'; END IF;
END $$;
ROLLBACK;
SELECT '405 bump_verification_digest contract passed' AS result;
