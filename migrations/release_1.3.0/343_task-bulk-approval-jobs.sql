-- 343 — Task bulk approval jobs: durable progress ledger for loaded-task approvals.
--
-- Why: the Tasks page can approve many loaded review tasks in the background.
-- The UI polls progress while the BFF drains selected task IDs in bounded
-- batches. Progress must survive serverless cold starts and cross-instance
-- polling; process memory is not reliable enough.
--
-- Affected projects:
--   - selltonai: POST /api/tasks/bulk-approve writes and updates this table;
--     POST /api/tasks/bulk-approve/status reads it for the live progress popup.
-- Deploy together: apply this migration before deploying the selltonai route
-- changes that write task_bulk_approval_jobs.
--
-- Additive + non-breaking. Safe to drop while empty.

CREATE TABLE IF NOT EXISTS public.task_bulk_approval_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  requested_by_user_id text,
  mode text NOT NULL DEFAULT 'selected' CHECK (mode IN ('selected', 'filtered')),
  status text NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'running', 'completed', 'failed', 'cancelled')),
  task_ids jsonb NOT NULL DEFAULT '[]'::jsonb,
  total_count integer NOT NULL DEFAULT 0 CHECK (total_count >= 0),
  processed_count integer NOT NULL DEFAULT 0 CHECK (processed_count >= 0),
  succeeded_count integer NOT NULL DEFAULT 0 CHECK (succeeded_count >= 0),
  failed_count integer NOT NULL DEFAULT 0 CHECK (failed_count >= 0),
  batch_count integer NOT NULL DEFAULT 0 CHECK (batch_count >= 0),
  last_error text,
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT task_bulk_approval_jobs_count_bounds CHECK (
    processed_count <= total_count
    AND succeeded_count <= total_count
    AND failed_count <= total_count
    AND succeeded_count + failed_count <= total_count
  )
);

CREATE INDEX IF NOT EXISTS idx_task_bulk_approval_jobs_org_created
  ON public.task_bulk_approval_jobs(organization_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_task_bulk_approval_jobs_org_status_created
  ON public.task_bulk_approval_jobs(organization_id, status, created_at DESC);

CREATE OR REPLACE FUNCTION public.update_task_bulk_approval_jobs_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS task_bulk_approval_jobs_updated_at ON public.task_bulk_approval_jobs;
CREATE TRIGGER task_bulk_approval_jobs_updated_at
  BEFORE UPDATE ON public.task_bulk_approval_jobs
  FOR EACH ROW
  EXECUTE FUNCTION public.update_task_bulk_approval_jobs_updated_at();

CREATE OR REPLACE FUNCTION public.increment_task_bulk_approval_job(
  p_job_id uuid,
  p_succeeded integer,
  p_failed integer,
  p_last_error text DEFAULT NULL
)
RETURNS void AS $$
WITH current_job AS (
  SELECT
    id,
    total_count,
    processed_count,
    GREATEST(total_count - processed_count, 0) AS remaining_count
  FROM public.task_bulk_approval_jobs
  WHERE id = p_job_id
    AND status IN ('queued', 'running')
),
delta AS (
  SELECT
    id,
    LEAST(GREATEST(p_succeeded, 0), remaining_count) AS succeeded_delta,
    LEAST(
      GREATEST(p_failed, 0),
      GREATEST(remaining_count - LEAST(GREATEST(p_succeeded, 0), remaining_count), 0)
    ) AS failed_delta
  FROM current_job
)
UPDATE public.task_bulk_approval_jobs
SET
  status = CASE WHEN status = 'queued' THEN 'running' ELSE status END,
  started_at = COALESCE(started_at, now()),
  processed_count = processed_count + delta.succeeded_delta + delta.failed_delta,
  succeeded_count = succeeded_count + delta.succeeded_delta,
  failed_count = failed_count + delta.failed_delta,
  batch_count = batch_count + CASE WHEN delta.succeeded_delta + delta.failed_delta > 0 THEN 1 ELSE 0 END,
  last_error = COALESCE(p_last_error, last_error),
  updated_at = now()
FROM delta
WHERE task_bulk_approval_jobs.id = delta.id;
$$ LANGUAGE sql;

CREATE OR REPLACE FUNCTION public.fail_remaining_task_bulk_approval_job(
  p_job_id uuid,
  p_last_error text
)
RETURNS void AS $$
UPDATE public.task_bulk_approval_jobs
SET
  status = 'failed',
  processed_count = total_count,
  failed_count = LEAST(total_count, failed_count + GREATEST(total_count - processed_count, 0)),
  last_error = COALESCE(p_last_error, last_error),
  completed_at = COALESCE(completed_at, now()),
  updated_at = now()
WHERE id = p_job_id
  AND status IN ('queued', 'running');
$$ LANGUAGE sql;

ALTER TABLE public.task_bulk_approval_jobs ENABLE ROW LEVEL SECURITY;

-- Org-scoped policies. The BFF uses service_role and bypasses RLS, but these
-- keep the table safe for future direct status/admin surfaces.
DROP POLICY IF EXISTS "Users can view task bulk approval jobs for their organization" ON public.task_bulk_approval_jobs;
CREATE POLICY "Users can view task bulk approval jobs for their organization" ON public.task_bulk_approval_jobs
  FOR SELECT USING (organization_id = current_setting('app.current_org_id', true));

DROP POLICY IF EXISTS "Users can insert task bulk approval jobs for their organization" ON public.task_bulk_approval_jobs;
CREATE POLICY "Users can insert task bulk approval jobs for their organization" ON public.task_bulk_approval_jobs
  FOR INSERT WITH CHECK (organization_id = current_setting('app.current_org_id', true));

DROP POLICY IF EXISTS "Users can update task bulk approval jobs for their organization" ON public.task_bulk_approval_jobs;
CREATE POLICY "Users can update task bulk approval jobs for their organization" ON public.task_bulk_approval_jobs
  FOR UPDATE USING (organization_id = current_setting('app.current_org_id', true));

COMMENT ON TABLE public.task_bulk_approval_jobs IS
  'Durable progress ledger for Tasks page bulk approvals. The BFF drains selected task IDs in bounded batches while the UI polls counters.';

-- Verify:
--   SELECT status, count(*), sum(total_count), sum(processed_count)
--   FROM public.task_bulk_approval_jobs GROUP BY status;
