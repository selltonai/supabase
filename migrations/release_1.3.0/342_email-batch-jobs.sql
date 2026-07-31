-- 342 — Email batch jobs (T-BATCH): durable tracker for autopilot follow-up
-- emails generated via the Anthropic Message Batches API.
--
-- Why: the follow-up cron generates + persists each review task SYNCHRONOUSLY,
-- but Message Batches are ASYNCHRONOUS (submit → poll minutes/hours → retrieve)
-- and ~50% cheaper. This row bridges the two: the (flag-gated) submit path
-- assembles all eligible contacts' writer requests, submits ONE batch, and
-- records the provider batch id + a per-request context map here; a separate
-- drain cron polls open jobs and, on completion, creates the review tasks.
--
-- request_context holds, per custom_id, exactly what the drain needs to create
-- the review task WITHOUT re-running generation:
--   [{ "custom_id", "contact_id", "campaign_id", "company_id", "thread_id",
--      "sequence_number", "mode", "metadata": {...} }, ...]
-- created_custom_ids is the idempotency guard — a re-poll never double-creates a
-- task for a custom_id already turned into one.
--
-- Affected projects:
--   - selltonai-modal: the batch submit + drain crons write/read this table
--     (service_role, bypasses RLS).
-- Deploy: apply this migration before enabling FOLLOWUP_BATCH_ENABLED on Modal.
--
-- Additive + non-breaking. Safe to drop while empty (feature is default-OFF).

CREATE TABLE IF NOT EXISTS public.email_batch_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  -- Anthropic Message Batch id (msgbatch_...). Unique — one row per submitted batch.
  provider_batch_id text NOT NULL,
  status text NOT NULL DEFAULT 'submitted'
    CHECK (status IN ('submitted', 'in_progress', 'completed', 'failed', 'expired', 'canceled')),
  request_count integer NOT NULL DEFAULT 0 CHECK (request_count >= 0),
  succeeded_count integer NOT NULL DEFAULT 0 CHECK (succeeded_count >= 0),
  errored_count integer NOT NULL DEFAULT 0 CHECK (errored_count >= 0),
  task_created_count integer NOT NULL DEFAULT 0 CHECK (task_created_count >= 0),
  -- Per-request task-creation context, keyed by custom_id (see header).
  request_context jsonb NOT NULL DEFAULT '[]'::jsonb,
  -- Idempotency: custom_ids already turned into review tasks by the drain.
  created_custom_ids jsonb NOT NULL DEFAULT '[]'::jsonb,
  source text NOT NULL DEFAULT 'followup_batch',
  poll_attempts integer NOT NULL DEFAULT 0 CHECK (poll_attempts >= 0),
  last_error text,
  submitted_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_email_batch_jobs_provider_batch_id
  ON public.email_batch_jobs(provider_batch_id);
CREATE INDEX IF NOT EXISTS idx_email_batch_jobs_org_id
  ON public.email_batch_jobs(organization_id);
-- Drain cron: pick the oldest not-yet-terminal job. Partial index keeps it tiny.
CREATE INDEX IF NOT EXISTS idx_email_batch_jobs_drainable
  ON public.email_batch_jobs(submitted_at)
  WHERE status IN ('submitted', 'in_progress');

CREATE OR REPLACE FUNCTION public.update_email_batch_jobs_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS email_batch_jobs_updated_at ON public.email_batch_jobs;
CREATE TRIGGER email_batch_jobs_updated_at
  BEFORE UPDATE ON public.email_batch_jobs
  FOR EACH ROW
  EXECUTE FUNCTION public.update_email_batch_jobs_updated_at();

ALTER TABLE public.email_batch_jobs ENABLE ROW LEVEL SECURITY;

-- Org-scoped policies (a future UI may show batch status). The crons use
-- service_role, which bypasses RLS.
DROP POLICY IF EXISTS "Users can view email batch jobs for their organization" ON public.email_batch_jobs;
CREATE POLICY "Users can view email batch jobs for their organization" ON public.email_batch_jobs
  FOR SELECT USING (organization_id = current_setting('app.current_org_id', true));

DROP POLICY IF EXISTS "Users can insert email batch jobs for their organization" ON public.email_batch_jobs;
CREATE POLICY "Users can insert email batch jobs for their organization" ON public.email_batch_jobs
  FOR INSERT WITH CHECK (organization_id = current_setting('app.current_org_id', true));

DROP POLICY IF EXISTS "Users can update email batch jobs for their organization" ON public.email_batch_jobs;
CREATE POLICY "Users can update email batch jobs for their organization" ON public.email_batch_jobs
  FOR UPDATE USING (organization_id = current_setting('app.current_org_id', true));

-- Verify:
--   SELECT status, count(*), sum(request_count), sum(task_created_count)
--   FROM public.email_batch_jobs GROUP BY status;
