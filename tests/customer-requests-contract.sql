-- KAN-322 FR-A9: migration 391's contract. Run by tests/run-customer-requests-contract.sh on a disposable database.
DO $$
DECLARE r record;
BEGIN
  -- anon and authenticated have no table privileges despite Supabase's default grants.
  IF has_table_privilege('anon', 'public.customer_requests', 'SELECT') OR has_table_privilege('authenticated', 'public.customer_requests', 'SELECT')
     OR has_table_privilege('anon', 'public.customer_requests', 'INSERT') OR has_table_privilege('authenticated', 'public.customer_requests', 'UPDATE') THEN
    RAISE EXCEPTION 'anon/authenticated still have table privileges';
  END IF;
  IF NOT has_table_privilege('service_role', 'public.customer_requests', 'INSERT') THEN RAISE EXCEPTION 'service_role cannot insert'; END IF;
  IF has_function_privilege('anon', 'public.update_customer_requests_updated_at()', 'EXECUTE') THEN RAISE EXCEPTION 'anon can execute the trigger function'; END IF;
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.customer_requests'::regclass) THEN RAISE EXCEPTION 'RLS is off'; END IF;

  -- Defaults and checks.
  INSERT INTO public.customer_requests (organization_id, user_id, type, body) VALUES ('org_a', 'user_1', 'feedback', 'It broke') RETURNING * INTO r;
  IF r.status <> 'new' OR r.details <> '{}'::jsonb OR r.slack_notified_at IS NOT NULL OR r.slack_attempts <> 0 OR r.slack_claimed_at IS NOT NULL THEN RAISE EXCEPTION 'bad defaults: %', row_to_json(r); END IF;
  BEGIN
    INSERT INTO public.customer_requests (organization_id, user_id, type) VALUES ('org_a', 'u', 'refund');
    RAISE EXCEPTION 'an unknown type was accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.customer_requests (organization_id, user_id, type, status) VALUES ('org_a', 'u', 'leave', 'closed');
    RAISE EXCEPTION 'an unknown status was accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.customer_requests (organization_id, user_id, type, body) VALUES ('org_a', 'u', 'feedback', repeat('x', 5001));
    RAISE EXCEPTION 'a body over 5000 characters was accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.customer_requests (organization_id, user_id, type) VALUES ('org_unknown', 'u', 'feedback');
    RAISE EXCEPTION 'an unknown organization was accepted';
  EXCEPTION WHEN foreign_key_violation THEN NULL; END;

  -- updated_at is set by the trigger on update (now() is fixed inside one transaction, so start from an old value).
  ALTER TABLE public.customer_requests DISABLE TRIGGER customer_requests_updated_at;
  UPDATE public.customer_requests SET updated_at = '2020-01-01' WHERE id = r.id;
  ALTER TABLE public.customer_requests ENABLE TRIGGER customer_requests_updated_at;
  UPDATE public.customer_requests SET status = 'done' WHERE id = r.id;
  IF (SELECT updated_at FROM public.customer_requests WHERE id = r.id) < '2021-01-01' THEN RAISE EXCEPTION 'updated_at did not move'; END IF;

  -- Deleting the organization deletes its requests.
  INSERT INTO public.customer_requests (organization_id, user_id, type) VALUES ('org_b', 'u', 'mailboxes');
  DELETE FROM public.organization WHERE id = 'org_b';
  IF EXISTS (SELECT 1 FROM public.customer_requests WHERE organization_id = 'org_b') THEN RAISE EXCEPTION 'cascade failed'; END IF;

  -- The bucket: private, images only, 5 MB.
  IF NOT EXISTS (SELECT 1 FROM storage.buckets WHERE id = 'customer-request-files' AND public = false AND file_size_limit = 5242880
                 AND allowed_mime_types = ARRAY['image/png', 'image/jpeg', 'image/webp', 'image/gif']::text[]) THEN
    RAISE EXCEPTION 'bucket missing or wrong';
  END IF;
END $$;

-- The org-scoped SELECT policy (second layer): an authenticated session with app.current_org_id sees only its rows,
-- were it granted SELECT. Granted here inside a transaction that is rolled back.
BEGIN;
GRANT SELECT ON public.customer_requests TO authenticated;
INSERT INTO public.organization VALUES ('org_c');
INSERT INTO public.customer_requests (organization_id, user_id, type) VALUES ('org_c', 'u', 'feedback');
SET LOCAL ROLE authenticated;
SET LOCAL app.current_org_id = 'org_a';
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM public.customer_requests WHERE organization_id <> 'org_a') THEN RAISE EXCEPTION 'policy leaks another organization'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.customer_requests) THEN RAISE EXCEPTION 'policy hides the own organization'; END IF;
END $$;
ROLLBACK;
SELECT 'customer_requests contract passed' AS result;
