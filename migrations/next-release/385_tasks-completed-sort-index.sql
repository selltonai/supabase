-- ============================================================
-- Migration: tasks-completed-sort-index (main: next-release/385, stage: next-release/385 — byte-identical)
-- Date:      2026-09-30
-- Purpose:   Make the Tasks page's Completed / Cancelled / Declined tabs read
--            the first page from an ordered index instead of sorting every
--            finished task of the org.
-- Projects:  selltonai-database/supabase (owner); reader: selltonai
--            GET /api/tasks (src/app/api/tasks/route.ts, terminal-status branch).
-- Contract:  Index + planner statistics only. No column, constraint, RLS,
--            request, response, auth, webhook, cron or queue contract changes.
--            Safe to drop.
-- Depends:   public.tasks (38), completed_at / updated_at / created_at, metadata.
--
-- Why: production 2026-09-30 08:39 UTC, Tasks -> Email -> Completed
--   [QueryOptimizer] tasks_query_<org>_completed_review_draft_0 took 8117ms
--   [TasksAPI] Error fetching tasks: { code: '57014' }  (statement timeout)
-- The terminal-status branch filters
--   organization_id = ? AND status = ? [AND task_type = ?]
--   AND (metadata->>'channel' = 'email' OR metadata->>'channel' IS NULL)   -- or = 'linkedin'
-- and orders by status, completed_at DESC NULLS LAST, updated_at DESC, created_at DESC.
--
-- Production already has the matching index (idx_tasks_org_status_completed_at,
-- applied by hand in June from the never-merged 329 on
-- fix/tasks-completed-query-perf-2026-06-16; it is not in the ledger). The
-- planner still does not use it. EXPLAIN on production (org with 10,277
-- completed review_draft tasks):
--   Limit -> Sort -> Bitmap Heap Scan (idx_tasks_org_type_status), rows=76
-- PostgreSQL has no statistics for metadata->>'channel' and guesses the channel
-- predicate keeps ~1% of rows. It then believes only ~76 rows match, so sorting
-- them looks cheaper than walking the ordered index. In reality ~90% match, so
-- it fetches and sorts every finished draft of the org, with the route's wide
-- select (body, pre_generated_copy, metadata), for each page it reads.
--
-- Design:
-- - CREATE INDEX IF NOT EXISTS with the June definition: a no-op on production
--   (the index exists), creates it where it is missing, and puts the DDL in the
--   repo. (organization_id, status) equality prefix, then the exact ORDER BY
--   suffix incl. NULLS LAST (DESC defaults to NULLS FIRST, which would not match).
--   task_type is left out so one index serves every terminal tab; it stays a
--   residual filter.
-- - CREATE STATISTICS on (metadata->>'channel') + ANALYZE: gives the planner the
--   real channel distribution (same pattern as linkedin-counterpart-lookup-indexes,
--   main 372 / stage 380). Reproduced on a local PG15 copy shaped like that org
--   (115k rows, 9,040 matching): without the statistics the planner picked the
--   same Bitmap Heap Scan + Sort as production; with them it walks
--   idx_tasks_org_status_completed_at for page 1 (0.12 ms), offset 900 (0.68 ms)
--   and the LinkedIn tab, at the default random_page_cost of 4.
-- - Locks: on production the index exists, so the file holds the table's SHARE
--   lock (blocks task writes, not reads) only for the ANALYZE, about a second on a
--   table this size. Where the index is missing, the build holds it until commit.
--   lock_timeout makes the file fail and roll back instead of queueing task
--   writers behind a long-running transaction; re-run it (idempotent). The
--   runner rejects CONCURRENTLY, so this is a plain CREATE INDEX.
--
-- Rollback (safe; nothing depends on these objects):
--   DROP STATISTICS IF EXISTS public.stx_tasks_metadata_channel;
--   (Keep idx_tasks_org_status_completed_at: production had it before this file.)
-- ============================================================

SET LOCAL lock_timeout = '10s';

CREATE INDEX IF NOT EXISTS idx_tasks_org_status_completed_at
  ON public.tasks (
    organization_id,
    status,
    completed_at DESC NULLS LAST,
    updated_at DESC,
    created_at DESC
  );

COMMENT ON INDEX public.idx_tasks_org_status_completed_at IS
  'Serves GET /api/tasks completed/cancelled/declined tabs: WHERE (organization_id, status[, task_type residual]) ORDER BY status, completed_at DESC NULLS LAST, updated_at DESC, created_at DESC. Pending-tab counterpart: idx_tasks_org_status_priority_created.';

CREATE STATISTICS IF NOT EXISTS public.stx_tasks_metadata_channel
  ON ((metadata ->> 'channel')) FROM public.tasks;

ANALYZE public.tasks;

-- Verification after apply:
-- SELECT indexname FROM pg_indexes
-- WHERE schemaname = 'public' AND indexname = 'idx_tasks_org_status_completed_at';
-- SELECT stxname FROM pg_statistic_ext WHERE stxname = 'stx_tasks_metadata_channel';
--
-- Plan check (substitute a large org; expect "Index Scan using
-- idx_tasks_org_status_completed_at", no Sort node, no Bitmap Heap Scan):
-- EXPLAIN SELECT id FROM public.tasks
-- WHERE organization_id = '<org>' AND status = 'completed' AND task_type = 'review_draft'
--   AND (metadata->>'channel' = 'email' OR metadata->>'channel' IS NULL)
-- ORDER BY status, completed_at DESC NULLS LAST, updated_at DESC, created_at DESC
-- LIMIT 100;
