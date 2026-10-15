-- ============================================================
-- Migration: close-usage-tables-to-browser-key (stage: next-release/394; renumber at promotion)
-- Date:      2026-10-14
-- Purpose:   KAN-333 task 1. `usage` and `usage_summary` carry an allow-all policy with no TO
--            (release_1.0.5/1_20250108_simple_usage_table.sql:221-222) and full grants to anon and authenticated, so the
--            browser's anon key (NEXT_PUBLIC_SUPABASE_ANON_KEY) can read, change or delete every workspace's usage.
--            `action_label_map` (249) has full grants to the same roles and no policy.
--              1. Drop both allow-all policies. RLS stays enabled: with no policy only service_role (BYPASSRLS) sees rows.
--              2. REVOKE ALL on the three tables and the sequences they own from anon and authenticated.
--              3. REVOKE ALL on the 15 views over `usage` from anon and authenticated. They are owned by supabase_admin
--                 and are not security_invoker, so they read `usage` past RLS: on stage, SET ROLE anon read 87 rows of
--                 usage_cost_daily before this migration. Closing the tables alone would leave them open.
-- Projects:  selltonai-database/supabase (owner). Readers are server-side with the service role: the web's
--            src/app/api/analytics/token-usage/*, src/app/api/linkedin/contacts/[id]/{posts,refresh}, src/lib/usage-events.ts
--            (supabaseAdmin); Modal's UsageService and BillingService; the backoffice (service-role keys). Two web helpers
--            fall back to the anon key when SUPABASE_SERVICE_ROLE_KEY is missing; after this they fail loudly.
-- Contract:  Grants and policies only. No table, column, function body, trigger or data change. service_role keeps
--            every privilege. Application code need not change.
-- Rollback:  migrations/next-release/rollback/394_close-usage-tables-to-browser-key.rollback.sql
-- ============================================================

DROP POLICY IF EXISTS "Allow all operations on usage" ON public.usage;
DROP POLICY IF EXISTS "Allow all operations on usage_summary" ON public.usage_summary;

ALTER TABLE public.usage ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.usage_summary ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.usage, public.usage_summary, public.action_label_map FROM anon, authenticated;
GRANT ALL ON TABLE public.usage, public.usage_summary, public.action_label_map TO service_role;

DO $$
DECLARE
  v_seq regclass;
BEGIN
  FOR v_seq IN
    SELECT s.oid::regclass
    FROM pg_class s
    JOIN pg_depend d ON d.objid = s.oid AND d.deptype IN ('a', 'i')
    WHERE s.relkind = 'S'
      AND d.refobjid IN ('public.usage'::regclass, 'public.usage_summary'::regclass, 'public.action_label_map'::regclass)
  LOOP
    EXECUTE format('REVOKE ALL ON SEQUENCE %s FROM anon, authenticated', v_seq);
    EXECUTE format('GRANT ALL ON SEQUENCE %s TO service_role', v_seq);
  END LOOP;
END;
$$;

-- Every view that reads one of the three tables, whatever it is called (15 on stage on 2026-10-14).
DO $$
DECLARE
  v_view regclass;
BEGIN
  FOR v_view IN
    SELECT DISTINCT v.oid::regclass
    FROM pg_depend d
    JOIN pg_rewrite r ON r.oid = d.objid
    JOIN pg_class v ON v.oid = r.ev_class
    WHERE d.refobjid IN ('public.usage'::regclass, 'public.usage_summary'::regclass, 'public.action_label_map'::regclass)
      AND v.relkind IN ('v', 'm')
      AND v.oid NOT IN ('public.usage'::regclass, 'public.usage_summary'::regclass, 'public.action_label_map'::regclass)
  LOOP
    EXECUTE format('REVOKE ALL ON TABLE %s FROM anon, authenticated', v_view);
    EXECUTE format('GRANT SELECT ON TABLE %s TO service_role', v_view);
  END LOOP;
END;
$$;

-- Verify (read-only; every row false except service_role):
--   SELECT t, has_table_privilege('anon', t, 'SELECT') anon_select, has_table_privilege('authenticated', t, 'SELECT') auth_select,
--          has_table_privilege('anon', t, 'INSERT,UPDATE,DELETE') anon_write, has_table_privilege('service_role', t, 'SELECT') service
--   FROM unnest(ARRAY['public.usage', 'public.usage_summary', 'public.action_label_map', 'public.usage_cost_daily']) AS t;
--   SELECT tablename, policyname FROM pg_policies WHERE schemaname = 'public' AND tablename IN ('usage', 'usage_summary');  -- no rows
--   SELECT DISTINCT v.relname FROM pg_depend d JOIN pg_rewrite r ON r.oid = d.objid JOIN pg_class v ON v.oid = r.ev_class
--   WHERE d.refobjid = 'public.usage'::regclass AND v.oid <> 'public.usage'::regclass
--     AND (has_table_privilege('anon', v.oid, 'SELECT') OR has_table_privilege('authenticated', v.oid, 'SELECT'));  -- no rows
--   With the anon key: GET /rest/v1/usage?limit=1 and /rest/v1/usage_cost_daily?limit=1 are refused (401/403).
