-- ============================================================
-- Migration: 440_close-usage-rollup-and-week-snapshot-to-browser-key (stage: next-release/440; renumber at promotion
--            if 440 is taken)
-- Date:      2026-11-16
-- Purpose:   G-W30 (selltonai docs/GAPS.md), release runbook v4 item A4. On production, main's
--            release_1.3.0/374_production-catch-up-usage-label-map.sql (applied 2026-10-27) created
--            public.analytics_usage_rollup(text, timestamptz, timestamptz, text, text) as SECURITY DEFINER with no
--            caller check and GRANT EXECUTE ... TO authenticated, after 390's revoke had already run there. So any
--            signed-in browser can read any workspace's usage and cost over /rest/v1/rpc/analytics_usage_rollup.
--            The same file granted public.billing_week_snapshot (no RLS) to authenticated; stage's 249 did the same,
--            and no migration on either line closed it. 394 closed action_label_map on both lines; 431 replaces a
--            different function and keeps its grants.
--              1. REVOKE ALL on every overload of analytics_usage_rollup, _v2 and _v3 from PUBLIC, anon and
--                 authenticated; GRANT EXECUTE to service_role (390's treatment; a no-op where 390 already did it).
--              2. REVOKE ALL on billing_week_snapshot from anon and authenticated; GRANT ALL to service_role; enable
--                 RLS with no policy, so only service_role (BYPASSRLS) and the owner see rows.
--              3. Fail the migration if any of them is still reachable by anon or authenticated, or service_role
--                 lost it (has_function_privilege / has_table_privilege).
-- Projects:  selltonai-database/supabase (owner). Callers, all server-side with the service role (checked 2026-11-16):
--            selltonai src/app/api/analytics/{phone-discovery,usage-costs/daily,usage-costs/monthly} (supabaseAdmin)
--            call analytics_usage_rollup; analytics_usage_rollup_v3 from src/app/api/analytics/usage-rollup (service
--            role key). billing_week_snapshot: no reader in selltonai, selltonai-modal, backoffice, gmail-api or the
--            engine (only the engine's pg test schema creates it).
-- Contract:  Grants and RLS only. No table, column, function body, trigger or data change. service_role keeps every
--            privilege. Application code need not change.
-- Rollback:  rollback/440_close-usage-rollup-and-week-snapshot-to-browser-key.rollback.sql (restores the hole).
-- ============================================================

SET LOCAL lock_timeout = '10s';

DO $$
DECLARE
  fn regprocedure;
BEGIN
  FOR fn IN
    SELECT p.oid::regprocedure
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prokind = 'f'
      AND p.proname IN ('analytics_usage_rollup', 'analytics_usage_rollup_v2', 'analytics_usage_rollup_v3')
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated', fn);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', fn);
  END LOOP;
END;
$$;

DO $$
DECLARE
  v_seq regclass;
BEGIN
  IF to_regclass('public.billing_week_snapshot') IS NULL THEN
    RETURN;
  END IF;
  EXECUTE 'REVOKE ALL ON TABLE public.billing_week_snapshot FROM anon, authenticated';
  EXECUTE 'GRANT ALL ON TABLE public.billing_week_snapshot TO service_role';
  EXECUTE 'ALTER TABLE public.billing_week_snapshot ENABLE ROW LEVEL SECURITY';
  FOR v_seq IN
    SELECT s.oid::regclass
    FROM pg_class s
    JOIN pg_depend d ON d.objid = s.oid AND d.deptype IN ('a', 'i')
    WHERE s.relkind = 'S' AND d.refobjid = 'public.billing_week_snapshot'::regclass
  LOOP
    EXECUTE format('REVOKE ALL ON SEQUENCE %s FROM anon, authenticated', v_seq);
    EXECUTE format('GRANT ALL ON SEQUENCE %s TO service_role', v_seq);
  END LOOP;
END;
$$;

-- The check the runbook asks for: the migration fails, and its transaction rolls back, if anything is still open.
DO $$
DECLARE
  still_open text;
  lost_service_role text;
BEGIN
  SELECT string_agg(p.oid::regprocedure::text, ', ')
  INTO still_open
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.prokind = 'f'
    AND p.proname IN ('analytics_usage_rollup', 'analytics_usage_rollup_v2', 'analytics_usage_rollup_v3')
    AND (has_function_privilege('anon', p.oid, 'EXECUTE') OR has_function_privilege('authenticated', p.oid, 'EXECUTE'));
  IF still_open IS NOT NULL THEN
    RAISE EXCEPTION '440: still executable by anon or authenticated: %', still_open;
  END IF;

  SELECT string_agg(p.oid::regprocedure::text, ', ')
  INTO lost_service_role
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.prokind = 'f'
    AND p.proname IN ('analytics_usage_rollup', 'analytics_usage_rollup_v2', 'analytics_usage_rollup_v3')
    AND NOT has_function_privilege('service_role', p.oid, 'EXECUTE');
  IF lost_service_role IS NOT NULL THEN
    RAISE EXCEPTION '440: service_role cannot execute: %', lost_service_role;
  END IF;

  IF to_regclass('public.billing_week_snapshot') IS NOT NULL THEN
    IF has_table_privilege('anon', 'public.billing_week_snapshot', 'SELECT,INSERT,UPDATE,DELETE')
       OR has_table_privilege('authenticated', 'public.billing_week_snapshot', 'SELECT,INSERT,UPDATE,DELETE') THEN
      RAISE EXCEPTION '440: billing_week_snapshot still open to anon or authenticated';
    END IF;
    IF NOT has_table_privilege('service_role', 'public.billing_week_snapshot', 'SELECT,INSERT,UPDATE,DELETE') THEN
      RAISE EXCEPTION '440: service_role lost billing_week_snapshot';
    END IF;
  END IF;
END;
$$;

-- Verify after the run (read-only; every anon/auth column false, every service column true):
--   SELECT p.oid::regprocedure AS fn, has_function_privilege('anon', p.oid, 'EXECUTE') anon,
--          has_function_privilege('authenticated', p.oid, 'EXECUTE') auth, has_function_privilege('service_role', p.oid, 'EXECUTE') service
--   FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--   WHERE n.nspname = 'public' AND p.proname IN ('analytics_usage_rollup', 'analytics_usage_rollup_v2', 'analytics_usage_rollup_v3');
--   SELECT has_table_privilege('anon', 'public.billing_week_snapshot', 'SELECT') anon,
--          has_table_privilege('authenticated', 'public.billing_week_snapshot', 'SELECT') auth,
--          has_table_privilege('service_role', 'public.billing_week_snapshot', 'SELECT') service,
--          (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.billing_week_snapshot'::regclass) rls;
