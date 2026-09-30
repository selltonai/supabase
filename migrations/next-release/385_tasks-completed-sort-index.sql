-- ============================================================
-- Migration: tasks-completed-sort-index (main: next-release/385, stage: next-release/385 — byte-identical)
-- Date:      2026-09-30
-- Purpose:   Serve the Tasks page's Completed / Cancelled / Declined tabs from
--            an index instead of sorting every finished task of the org.
-- Projects:  selltonai-database/supabase (owner); reader: selltonai
--            GET /api/tasks (src/app/api/tasks/route.ts, terminal-status branch).
-- Contract:  Index-only. No column, constraint, RLS, request, response, auth,
--            webhook, cron or queue contract changes. Safe to drop.
-- Depends:   public.tasks (38), completed_at / updated_at / created_at.
-- Origin:    written 2026-06-16 as 329_add_tasks_completed_sort_index on the
--            never-merged branch fix/tasks-completed-query-perf-2026-06-16;
--            renumbered here with the same index definition.
--
-- Why: production 2026-09-30 08:39 UTC, Tasks -> Email -> Completed
--   [QueryOptimizer] tasks_query_<org>_completed_review_draft_0 took 8117ms
--   [TasksAPI] Error fetching tasks: { code: '57014' }  (statement timeout)
-- The terminal-status branch of GET /api/tasks filters
--   organization_id = ? AND status = ? [AND task_type = ?] [AND channel]
-- and orders by
--   status, completed_at DESC NULLS LAST, updated_at DESC, created_at DESC.
-- The pending branch has a matching index (185 idx_tasks_org_status_priority_created);
-- this branch has none. idx_tasks_org_completed (200) lacks status, so the planner
-- filters through idx_tasks_org_type_status and SORTS every matching row before
-- returning the first page. The route reads up to 10 pages of 100 rows per request
-- (it filters some rows in code), so the sort repeats per page. Stage has the same
-- code and the same indexes; its orgs are small enough that the sort finishes.
--
-- Design:
-- - (organization_id, status) equality prefix, then the exact ORDER BY suffix,
--   including NULLS LAST (PostgreSQL's DESC default is NULLS FIRST, which would
--   not match). The planner walks the index in order and stops at the LIMIT.
-- - task_type is left out on purpose: the "all completed" view has no task_type
--   filter, and review_draft dominates finished tasks, so it stays a cheap
--   residual filter. One index serves every terminal tab.
-- - Plain CREATE INDEX (the runner rejects the non-locking variant): the build
--   takes a SHARE lock on public.tasks that blocks task writes (inserts, updates,
--   approvals) until the file commits; reads are not blocked. lock_timeout makes
--   the file fail and roll back instead of queueing every task writer behind a
--   long-running transaction; re-run it (idempotent). Apply at a quiet hour,
--   outside LinkedIn send windows.
--
-- Rollback (safe; nothing depends on this object):
--   DROP INDEX IF EXISTS public.idx_tasks_org_status_completed_at;
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

-- Verification after apply:
-- SELECT indexname, indexdef FROM pg_indexes
-- WHERE schemaname = 'public' AND indexname = 'idx_tasks_org_status_completed_at';
--
-- Plan check (substitute a real org; expect "Index Scan using
-- idx_tasks_org_status_completed_at" and no Sort node):
-- EXPLAIN SELECT id FROM public.tasks
-- WHERE organization_id = '<org>' AND status = 'completed' AND task_type = 'review_draft'
--   AND (metadata->>'channel' = 'email' OR metadata->>'channel' IS NULL)
-- ORDER BY status, completed_at DESC NULLS LAST, updated_at DESC, created_at DESC
-- LIMIT 100;
