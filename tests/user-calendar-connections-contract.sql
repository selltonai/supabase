-- KAN-309: migration 404's contract. Run by tests/run-user-calendar-connections-contract.sh on a disposable database,
-- after the migration has been applied twice (idempotency).
DO $$
DECLARE r record;
BEGIN
  -- anon and authenticated have no privileges despite Supabase's default grants; the service role has what it needs.
  IF has_table_privilege('anon', 'public.user_calendar_connections', 'SELECT')
     OR has_table_privilege('authenticated', 'public.user_calendar_connections', 'SELECT')
     OR has_table_privilege('authenticated', 'public.user_calendar_connections', 'INSERT')
     OR has_table_privilege('authenticated', 'public.user_calendar_connections', 'UPDATE')
     OR has_table_privilege('authenticated', 'public.user_calendar_connections', 'DELETE') THEN
    RAISE EXCEPTION 'anon/authenticated still have table privileges';
  END IF;
  IF NOT (has_table_privilege('service_role', 'public.user_calendar_connections', 'SELECT')
          AND has_table_privilege('service_role', 'public.user_calendar_connections', 'INSERT')
          AND has_table_privilege('service_role', 'public.user_calendar_connections', 'UPDATE')
          AND has_table_privilege('service_role', 'public.user_calendar_connections', 'DELETE')) THEN
    RAISE EXCEPTION 'service_role is missing a privilege';
  END IF;
  IF has_function_privilege('anon', 'public.update_user_calendar_connections_updated_at()', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.update_user_calendar_connections_updated_at()', 'EXECUTE') THEN
    RAISE EXCEPTION 'anon/authenticated can execute the trigger function';
  END IF;
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.user_calendar_connections'::regclass) THEN RAISE EXCEPTION 'RLS is off'; END IF;
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'user_calendar_connections') THEN
    RAISE EXCEPTION 'a policy exists; the table is deny-by-default';
  END IF;
  IF (SELECT count(*) FROM pg_trigger WHERE tgrelid = 'public.user_calendar_connections'::regclass AND NOT tgisinternal) <> 1 THEN
    RAISE EXCEPTION 'expected exactly one trigger after two applies';
  END IF;

  -- Defaults. A booking link alone is a valid row (the booking-link-only slice).
  INSERT INTO public.user_calendar_connections (organization_id, user_id, booking_url)
  VALUES ('org_a', 'user_1', 'https://cal.com/one/intro') RETURNING * INTO r;
  IF r.provider <> 'cal_com' OR r.status <> 'active' OR r.api_key_ciphertext IS NOT NULL OR r.id IS NULL THEN
    RAISE EXCEPTION 'bad defaults: %', row_to_json(r);
  END IF;
  -- A sealed key is accepted.
  INSERT INTO public.user_calendar_connections (organization_id, user_id, event_type_id, timezone, api_key_ciphertext, api_key_last4)
  VALUES ('org_b', 'user_1', '123456', 'Europe/Skopje', 'v1:aXY=:Y2lwaGVy', 'abcd');

  -- One connection per person, workspace and provider (the BFF upserts on exactly these columns).
  BEGIN
    INSERT INTO public.user_calendar_connections (organization_id, user_id) VALUES ('org_a', 'user_1');
    RAISE EXCEPTION 'a second connection for the same person and workspace was accepted';
  EXCEPTION WHEN unique_violation THEN NULL; END;
  INSERT INTO public.user_calendar_connections (organization_id, user_id, booking_url)
  VALUES ('org_a', 'user_1', 'https://cal.com/one/new')
  ON CONFLICT (organization_id, user_id, provider) DO UPDATE SET booking_url = EXCLUDED.booking_url;
  IF (SELECT booking_url FROM public.user_calendar_connections WHERE organization_id = 'org_a' AND user_id = 'user_1') <> 'https://cal.com/one/new' THEN
    RAISE EXCEPTION 'the upsert target does not match the unique constraint';
  END IF;

  -- CHECKs: a plaintext key, a non-https link, a non-numeric event type, an unknown provider/status, a long last4.
  BEGIN
    INSERT INTO public.user_calendar_connections (organization_id, user_id, api_key_ciphertext) VALUES ('org_a', 'user_2', 'cal_live_plaintextkey');
    RAISE EXCEPTION 'a plaintext key was accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.user_calendar_connections (organization_id, user_id, booking_url) VALUES ('org_a', 'user_2', 'http://cal.com/x');
    RAISE EXCEPTION 'an http link was accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.user_calendar_connections (organization_id, user_id, booking_url) VALUES ('org_a', 'user_2', 'https://cal.com/a b');
    RAISE EXCEPTION 'a link with a space was accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.user_calendar_connections (organization_id, user_id, booking_url) VALUES ('org_a', 'user_2', 'https://' || repeat('x', 500));
    RAISE EXCEPTION 'a link over 500 characters was accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.user_calendar_connections (organization_id, user_id, event_type_id) VALUES ('org_a', 'user_2', '12a');
    RAISE EXCEPTION 'a non-numeric event type was accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.user_calendar_connections (organization_id, user_id, provider) VALUES ('org_a', 'user_2', 'calendly');
    RAISE EXCEPTION 'an unknown provider was accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.user_calendar_connections (organization_id, user_id, status) VALUES ('org_a', 'user_2', 'revoked');
    RAISE EXCEPTION 'an unknown status was accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.user_calendar_connections (organization_id, user_id, api_key_last4) VALUES ('org_a', 'user_2', '12345');
    RAISE EXCEPTION 'a last4 over 4 characters was accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.user_calendar_connections (organization_id, user_id) VALUES ('org_unknown', 'user_2');
    RAISE EXCEPTION 'an unknown organization was accepted';
  EXCEPTION WHEN foreign_key_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.user_calendar_connections (organization_id, user_id) VALUES ('org_a', 'user_unknown');
    RAISE EXCEPTION 'an unknown user was accepted';
  EXCEPTION WHEN foreign_key_violation THEN NULL; END;

  -- updated_at is set by the trigger on update (now() is fixed inside one transaction, so start from an old value).
  ALTER TABLE public.user_calendar_connections DISABLE TRIGGER user_calendar_connections_updated_at;
  UPDATE public.user_calendar_connections SET updated_at = '2020-01-01' WHERE id = r.id;
  ALTER TABLE public.user_calendar_connections ENABLE TRIGGER user_calendar_connections_updated_at;
  UPDATE public.user_calendar_connections SET status = 'invalid' WHERE id = r.id;
  IF (SELECT updated_at FROM public.user_calendar_connections WHERE id = r.id) < '2021-01-01' THEN RAISE EXCEPTION 'updated_at did not move'; END IF;

  -- Deleting the organization or the user deletes their connections.
  INSERT INTO public.user_calendar_connections (organization_id, user_id) VALUES ('org_b', 'user_2');
  DELETE FROM public.organization WHERE id = 'org_b';
  IF EXISTS (SELECT 1 FROM public.user_calendar_connections WHERE organization_id = 'org_b') THEN RAISE EXCEPTION 'organization cascade failed'; END IF;
  DELETE FROM public."user" WHERE id = 'user_1';
  IF EXISTS (SELECT 1 FROM public.user_calendar_connections WHERE user_id = 'user_1') THEN RAISE EXCEPTION 'user cascade failed'; END IF;
END $$;

-- Deny by default is the second layer: even if SELECT is granted back to authenticated, and the session claims its
-- organization the 338 way, no row is visible. Granted inside a transaction that is rolled back.
BEGIN;
INSERT INTO public."user" VALUES ('user_3', 'three@example.com');
INSERT INTO public.user_calendar_connections (organization_id, user_id, api_key_ciphertext) VALUES ('org_a', 'user_3', 'v1:aXY=:Y2lwaGVy');
GRANT SELECT ON public.user_calendar_connections TO authenticated;
SET LOCAL ROLE authenticated;
SET LOCAL app.current_org_id = 'org_a';
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM public.user_calendar_connections) THEN RAISE EXCEPTION 'a stray grant exposes calendar connections'; END IF;
END $$;
RESET ROLE;
-- The service role (BYPASSRLS on Supabase) reads it.
SET LOCAL ROLE service_role;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.user_calendar_connections WHERE user_id = 'user_3') THEN RAISE EXCEPTION 'the service role cannot read'; END IF;
END $$;
ROLLBACK;

-- The rollback removes the table and the function.
BEGIN;
\ir ../migrations/next-release/rollback/404_user-calendar-connections.rollback.sql
DO $$ BEGIN
  IF to_regclass('public.user_calendar_connections') IS NOT NULL
     OR to_regprocedure('public.update_user_calendar_connections_updated_at()') IS NOT NULL THEN
    RAISE EXCEPTION 'the 404 rollback left objects behind';
  END IF;
END $$;
ROLLBACK;
SELECT '404 user_calendar_connections contract passed' AS result;
