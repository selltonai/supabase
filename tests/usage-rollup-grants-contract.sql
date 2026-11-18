-- Migration 440's contract: the rollup functions and billing_week_snapshot are closed to the browser's roles and open
-- to service_role; a signed-in caller is refused; the rollback reopens exactly 374's hole. Run by
-- tests/run-usage-rollup-grants-contract.sh on a disposable database, after the fixture and 440 (twice).
DO $$
DECLARE
  f text;
BEGIN
  FOREACH f IN ARRAY ARRAY[
    'public.analytics_usage_rollup(text, timestamptz, timestamptz, text, text)',
    'public.analytics_usage_rollup_v2(text)',
    'public.analytics_usage_rollup_v3(text)'
  ] LOOP
    IF has_function_privilege('anon', f, 'EXECUTE') OR has_function_privilege('authenticated', f, 'EXECUTE') THEN
      RAISE EXCEPTION '% still executable by a browser role', f;
    END IF;
    IF NOT has_function_privilege('service_role', f, 'EXECUTE') THEN
      RAISE EXCEPTION '% lost service_role', f;
    END IF;
  END LOOP;
  IF has_table_privilege('anon', 'public.billing_week_snapshot', 'SELECT,INSERT,UPDATE,DELETE')
     OR has_table_privilege('authenticated', 'public.billing_week_snapshot', 'SELECT,INSERT,UPDATE,DELETE') THEN
    RAISE EXCEPTION 'billing_week_snapshot still open to a browser role';
  END IF;
  IF NOT has_table_privilege('service_role', 'public.billing_week_snapshot', 'SELECT,INSERT,UPDATE,DELETE') THEN
    RAISE EXCEPTION 'billing_week_snapshot lost service_role';
  END IF;
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.billing_week_snapshot'::regclass) THEN
    RAISE EXCEPTION 'billing_week_snapshot has no RLS';
  END IF;
END $$;

-- As the roles themselves: authenticated is refused, service_role still reads.
SET ROLE authenticated;
DO $$ BEGIN
  BEGIN
    PERFORM * FROM public.analytics_usage_rollup('org_a', now() - interval '7 days', now(), 'day', NULL);
    RAISE EXCEPTION 'authenticated ran analytics_usage_rollup';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    PERFORM 1 FROM public.billing_week_snapshot;
    RAISE EXCEPTION 'authenticated read billing_week_snapshot';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SET ROLE service_role;
DO $$ BEGIN
  PERFORM * FROM public.analytics_usage_rollup('org_a', now() - interval '7 days', now(), 'day', NULL);
  IF (SELECT count(*) FROM public.billing_week_snapshot) <> 1 THEN RAISE EXCEPTION 'service_role lost the rows'; END IF;
END $$;
RESET ROLE;

-- The rollback reopens 374's hole, and only it.
BEGIN;
\i migrations/next-release/rollback/440_close-usage-rollup-and-week-snapshot-to-browser-key.rollback.sql
DO $$ BEGIN
  IF NOT has_function_privilege('authenticated', 'public.analytics_usage_rollup(text, timestamptz, timestamptz, text, text)', 'EXECUTE')
     OR NOT has_table_privilege('authenticated', 'public.billing_week_snapshot', 'SELECT') THEN
    RAISE EXCEPTION 'rollback did not restore 374''s grants';
  END IF;
  IF has_function_privilege('authenticated', 'public.analytics_usage_rollup_v2(text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'rollback reopened _v2, which 390 had closed';
  END IF;
  IF (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.billing_week_snapshot'::regclass) THEN
    RAISE EXCEPTION 'rollback left RLS on';
  END IF;
END $$;
ROLLBACK;
SELECT 'usage rollup grants contract passed' AS result;
