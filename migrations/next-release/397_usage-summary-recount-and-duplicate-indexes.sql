-- ============================================================
-- Migration: usage-summary-recount-and-duplicate-indexes (stage: next-release/397; renumber at promotion)
-- Date:      2026-10-14
-- Purpose:   KAN-333 task 8.
--              1. update_usage_summary() (only defined in release_1.0.5/1_20250108_simple_usage_table.sql; the live stage
--                 body is the one below without the change) recounted COUNT(DISTINCT session_id) over the org's whole
--                 day on every usage insert, web and phone. Nothing on screen reads unique_sessions (only the unlinked
--                 token-usage summary route selects it), so the totals' upsert stays and unique_sessions is no longer
--                 maintained: 0 on insert, unchanged on update.
--              2. idx_usage_org_created_desc and idx_usage_org_period are the same index as idx_usage_org_created,
--                 (organization_id, created_at DESC) (pg_indexes, stage 2026-10-14). Drop the two, keep idx_usage_org_created.
--                 Plain DROP INDEX: the Hetzner runner refuses CONCURRENTLY. On stage the indexes are 2.8 MB each. On
--                 production (1.9M rows, 153 MB each) DROP INDEX takes a brief ACCESS EXCLUSIVE lock on usage and waits
--                 for running queries; run it off-peak or through a reviewed CONCURRENTLY runbook.
-- Projects:  selltonai-database/supabase (owner). usage_summary.unique_sessions reader: the web's
--            src/app/api/analytics/token-usage/summary/route.ts (not in the menu). No application change needed.
-- Rollback:  migrations/next-release/rollback/397_usage-summary-recount-and-duplicate-indexes.rollback.sql
-- ============================================================

CREATE OR REPLACE FUNCTION public.update_usage_summary()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    INSERT INTO usage_summary (
        organization_id,
        provider,
        model_name,
        date,
        total_api_calls,
        total_input_tokens,
        total_output_tokens,
        total_tokens,
        unique_sessions
    ) VALUES (
        NEW.organization_id,
        NEW.provider,
        NEW.model_name,
        DATE(NEW.created_at),
        NEW.api_calls,
        NEW.input_tokens,
        NEW.output_tokens,
        NEW.total_tokens,
        0  -- 397: unique_sessions is no longer maintained
    )
    ON CONFLICT (organization_id, provider, model_name, date)
    DO UPDATE SET
        total_api_calls = usage_summary.total_api_calls + NEW.api_calls,
        total_input_tokens = usage_summary.total_input_tokens + NEW.input_tokens,
        total_output_tokens = usage_summary.total_output_tokens + NEW.output_tokens,
        total_tokens = usage_summary.total_tokens + NEW.total_tokens,
        updated_at = NOW();
    
    RETURN NEW;
END;
$function$;

COMMENT ON COLUMN public.usage_summary.unique_sessions IS
  'No longer maintained since migration 397 (KAN-333, 2026-10-14): 0 for new rows, frozen for old ones.';

DROP INDEX IF EXISTS public.idx_usage_org_created_desc;
DROP INDEX IF EXISTS public.idx_usage_org_period;

-- Verify (read-only):
--   SELECT position('COUNT(DISTINCT' IN pg_get_functiondef('public.update_usage_summary()'::regprocedure));  -- 0
--   SELECT indexname FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'usage'
--     AND indexname IN ('idx_usage_org_created', 'idx_usage_org_created_desc', 'idx_usage_org_period');  -- idx_usage_org_created only
