-- Migration: 329_add_tasks_completed_sort_index
-- Description: Fix statement-timeout (57014) on the Tasks list for data-heavy orgs.
--
--   Symptom (prod, 2026-06-16):
--     [QueryOptimizer] tasks_query_org_<ORG>_completed_review_draft_0 took 8179ms
--     [TasksAPI] Error fetching tasks: { code: '57014', message:
--       'canceling statement due to statement timeout' }
--
--   Root cause (code-verified, not assumed): GET /api/tasks orders the
--   completed / cancelled / declined branch by
--       ORDER BY status, completed_at DESC NULLS LAST, updated_at DESC, created_at DESC
--   filtered by (organization_id, status[, task_type]). The PENDING branch has a
--   covering index — idx_tasks_org_status_priority_created
--   (organization_id, status, priority_rank, created_at DESC) — so it stays fast.
--   The terminal-status branch has NO index pairing (organization_id, status) with
--   completed_at. The closest, idx_tasks_org_completed (organization_id, completed_at)
--   WHERE completed_at IS NOT NULL, lacks status, so the planner instead matches the
--   filter via idx_tasks_org_type_status and then SORTS every matching row by
--   completed_at. For an org with many completed review_draft tasks that sort exceeds
--   the ~8s statement_timeout. (The route's `x-request-timeout: 30s` is a client/PostgREST
--   hint and does NOT raise the Postgres statement_timeout — the real wall.)
--
--   Fix: one composite index whose ordered suffix exactly matches the terminal-status
--   ORDER BY after the (organization_id, status) equality prefix. The planner can then
--   return rows in index order and stop at LIMIT — no full sort — regardless of org size.
--   task_type (e.g. review_draft) stays a cheap residual filter during the scan, so this
--   one index serves both the per-type review tabs AND the "all" completed view.
--
-- Author: perf fix (tasks list timeout)
-- Date: 2026-06-16
--
-- Locking note: plain CREATE INDEX (not CONCURRENTLY) — the Supabase SQL editor
--   wraps statements in a transaction, and CONCURRENTLY cannot run in a txn block
--   (ERROR 25001). This matches the repo's existing convention on this same table
--   (e.g. migration 327 idx_tasks_dashboard_email_sent_rollup). The build takes a
--   SHARE lock that briefly blocks tasks WRITES (insert/update/delete) — reads are
--   NOT blocked — for the seconds it takes to build a btree. Apply during lower
--   traffic if the org is very large.
--
--   ZERO-WRITE-BLOCK ALTERNATIVE (very large tasks tables): run this instead via a
--   direct psql / pooler connection (NOT the SQL editor, which forces a txn):
--     CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_tasks_org_status_completed_at
--       ON public.tasks (organization_id, status, completed_at DESC NULLS LAST,
--                        updated_at DESC, created_at DESC);
--   then run the COMMENT below. Same index either way.

CREATE INDEX IF NOT EXISTS idx_tasks_org_status_completed_at
  ON public.tasks (
    organization_id,
    status,
    completed_at DESC NULLS LAST,
    updated_at DESC,
    created_at DESC
  );

COMMENT ON INDEX public.idx_tasks_org_status_completed_at IS
  'Serves GET /api/tasks completed/cancelled/declined branch: WHERE (organization_id, status[, task_type residual]) ORDER BY completed_at DESC, updated_at DESC, created_at DESC. Mirror of idx_tasks_org_status_priority_created which serves the pending branch. Added migration 329 to fix 57014 statement timeouts on data-heavy orgs.';
