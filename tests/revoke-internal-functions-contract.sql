-- S10 / migration 390 contract (runs after the migration has been applied twice). Disposable database only.
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid, p.oid::regprocedure AS fn, p.prorettype = 'trigger'::regtype AS is_trigger
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname IN (
      'claim_due_sequence_actions', 'delete_organization_file_fast', 'get_organization_summary',
      'analytics_usage_rollup', 'usage_analytics_projection_contribution', 'log_file_upload',
      'reserve_billing_invoice_number')
  LOOP
    IF has_function_privilege('anon', r.oid, 'EXECUTE') OR has_function_privilege('authenticated', r.oid, 'EXECUTE') THEN
      RAISE EXCEPTION 'still exposed: %', r.fn;
    END IF;
    IF NOT r.is_trigger AND NOT has_function_privilege('service_role', r.oid, 'EXECUTE') THEN
      RAISE EXCEPTION 'service_role lost: %', r.fn;
    END IF;
  END LOOP;
  -- Both overloads were covered.
  IF (SELECT count(*) FROM pg_proc WHERE proname = 'analytics_usage_rollup'
      AND NOT has_function_privilege('anon', oid, 'EXECUTE')) <> 2 THEN
    RAISE EXCEPTION 'an overload of analytics_usage_rollup kept its grant';
  END IF;
  -- Not on the list: untouched.
  IF NOT has_function_privilege('anon', 'public.keep_public_helper()', 'EXECUTE') THEN
    RAISE EXCEPTION 'an unlisted function lost its grant';
  END IF;
END $$;

-- anon is refused; service_role still calls; the trigger still fires for a service_role insert.
SET ROLE anon;
DO $$ BEGIN
  PERFORM public.claim_due_sequence_actions(now(), now(), 5);
  RAISE EXCEPTION 'anon could call claim_due_sequence_actions';
EXCEPTION WHEN insufficient_privilege THEN NULL;
END $$;
RESET ROLE;

SET ROLE service_role;
DO $$ BEGIN
  IF public.claim_due_sequence_actions(now(), now(), 5) <> 5 THEN RAISE EXCEPTION 'service_role call failed'; END IF;
END $$;
INSERT INTO public.organization_files (name) VALUES ('deck.pdf');
RESET ROLE;
DO $$ BEGIN
  IF (SELECT count(*) FROM public.file_upload_log) <> 1 THEN RAISE EXCEPTION 'the revoked trigger function did not fire'; END IF;
END $$;
