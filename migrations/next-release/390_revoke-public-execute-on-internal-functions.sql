-- Migration: 390_revoke-public-execute-on-internal-functions
-- Ticket: S10 (KAN-322 work order 2026-10-05 §8). Confirmed on stage by probes 2-3 on 2026-10-07.
--
-- Problem
--   Supabase grants every new function in `public` to anon and authenticated (default privileges), and
--   PUBLIC holds EXECUTE on functions by default. These functions never revoked it, so the anon key that
--   ships to every browser (NEXT_PUBLIC_SUPABASE_ANON_KEY) can call them over PostgREST
--   (`/rest/v1/rpc/<name>`). Several are SECURITY DEFINER and act on every workspace:
--     claim_due_sequence_actions        claims every workspace's due LinkedIn actions
--     delete_organization_file_fast     deletes a workspace's file rows and short links
--     apply_/sync_/backfill_/complete_  write the usage projection
--     analytics_usage_rollup[_v2|_v3]   read any workspace's usage and cost
--     get_organization_summary, get_companies_by_campaign   read any workspace's data
--     reserve_billing_invoice_number    reserves (burns) invoice numbers; 317 revoked PUBLIC only, which
--                                       leaves Supabase's direct anon/authenticated default grants in place
--
-- Who still calls them, and how (checked 2026-10-07 on selltonai origin/main + origin/stage, modal
-- production + stage, backoffice master, gmail-api, vector-api). Every caller is server-side and uses the
-- service role key; five selltonai callers and Modal's connection manager FALL BACK to the anon key only
-- when SUPABASE_SERVICE_ROLE_KEY is missing (a misconfigured environment, never production, where
-- supabaseAdmin already requires the key). After this migration such a misconfiguration fails instead of
-- quietly running as anon. Callers:
--     claim_due_sequence_actions   api/internal/sequence/claim/route.ts (supabaseAdmin)
--     analytics_usage_rollup       api/analytics/{phone-discovery,usage-costs/daily,usage-costs/monthly} (supabaseAdmin)
--     analytics_usage_rollup_v3    api/analytics/usage-rollup/route.ts (SUPABASE_SERVICE_ROLE_KEY)
--     delete_organization_file_fast services/files.service.ts (SUPABASE_SERVICE_ROLE_KEY)
--     get_companies_by_campaign    api/companies/route.ts (SUPABASE_SERVICE_ROLE_KEY)
--   selltonai-modal:
--     reserve_billing_invoice_number services/billing_service.py:2145 (connection_manager, service role)
--   No pg_cron job, RLS policy or SECURITY INVOKER function calls any of them. apply_usage_analytics_
--   projection_delta is called only inside SECURITY DEFINER functions (they run as the owner).
--   The deal and file-upload functions are trigger functions: PostgreSQL checks EXECUTE on a trigger
--   function when the trigger is created, never when it fires.
--
-- Change
--   For every overload of each name below that exists in this database: REVOKE ALL FROM PUBLIC, anon,
--   authenticated; GRANT EXECUTE TO service_role unless it is a trigger function. Then fail the whole
--   migration if anon or authenticated can still execute any of them (a REVOKE by a role without the
--   privilege is only a WARNING in PostgreSQL), or if service_role lost a callable one.
--   Idempotent. Names absent from a database are skipped (stage and production differ). No data change.
--   Default privileges are NOT changed here (probe 4 decides that); every new public function keeps
--   revoking explicitly, as 386-388 do.
--
-- Undo (only if a caller was missed): GRANT EXECUTE ON FUNCTION public.<name>(<args>) TO authenticated;

DO $$
DECLARE
  internal_functions CONSTANT text[] := ARRAY[
    'claim_due_sequence_actions',
    'delete_organization_file_fast',
    'get_organization_summary',
    'get_companies_by_campaign',
    'reserve_billing_invoice_number',
    'analytics_usage_rollup',
    'analytics_usage_rollup_v2',
    'analytics_usage_rollup_v3',
    'apply_usage_analytics_projection_delta',
    'sync_usage_analytics_projection',
    'backfill_usage_analytics_projection',
    'complete_usage_analytics_projection_backfill',
    'usage_analytics_projection_contribution',
    'log_file_upload',
    'bump_crm_deal_last_activity',
    'audit_crm_deal_change',
    'audit_crm_deal_task',
    'audit_crm_deal_snooze_change',
    'sync_crm_deal_from_company_contact',
    'sync_crm_deal_from_contact_stage',
    'sync_crm_deal_owner_tasks',
    'cancel_crm_deal_tasks_on_close',
    'notify_crm_deal_lifecycle'
  ];
  fn record;
  touched integer := 0;
  still_exposed text;
  lost_service_role text;
BEGIN
  FOR fn IN
    SELECT p.oid::regprocedure AS signature, p.prorettype = 'trigger'::regtype AS is_trigger
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prokind = 'f' AND p.proname = ANY (internal_functions)
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated', fn.signature);
    IF NOT fn.is_trigger THEN
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', fn.signature);
    END IF;
    touched := touched + 1;
  END LOOP;

  SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.proname)
  INTO still_exposed
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.prokind = 'f' AND p.proname = ANY (internal_functions)
    AND (has_function_privilege('anon', p.oid, 'EXECUTE') OR has_function_privilege('authenticated', p.oid, 'EXECUTE'));
  IF still_exposed IS NOT NULL THEN
    RAISE EXCEPTION '390: anon or authenticated can still execute: %', still_exposed;
  END IF;

  SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.proname)
  INTO lost_service_role
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.prokind = 'f' AND p.proname = ANY (internal_functions)
    AND p.prorettype <> 'trigger'::regtype
    AND NOT has_function_privilege('service_role', p.oid, 'EXECUTE');
  IF lost_service_role IS NOT NULL THEN
    RAISE EXCEPTION '390: service_role cannot execute: %', lost_service_role;
  END IF;

  RAISE NOTICE '390: revoked anon/authenticated/PUBLIC on % function(s)', touched;
END $$;

-- Verify (read-only). Expect zero rows: no SECURITY DEFINER function in public that anon or authenticated
-- can execute, except any a later review deliberately keeps public (none today).
-- SELECT p.oid::regprocedure AS fn,
--        has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_exec,
--        has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_exec
-- FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
-- WHERE n.nspname = 'public' AND p.prosecdef AND p.prokind = 'f'
--   AND (has_function_privilege('anon', p.oid, 'EXECUTE') OR has_function_privilege('authenticated', p.oid, 'EXECUTE'))
-- ORDER BY 1;
