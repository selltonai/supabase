-- ============================================================
-- Durable campaign start jobs
-- Projects:
--   - selltonai: queues campaign starts and polls job status
--   - selltonai-modal: owns campaign start execution and progress writes
-- Purpose:
--   Move large-list campaign starts out of the Vercel request lifecycle while
--   preserving observable progress for CRM-list and custom audience campaigns.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.campaign_start_jobs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id TEXT NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  campaign_id UUID NOT NULL REFERENCES public.campaigns(id) ON DELETE CASCADE,
  requested_by_user_id TEXT,
  requested_by_user_email TEXT,
  status TEXT NOT NULL DEFAULT 'queued',
  phase TEXT NOT NULL DEFAULT 'queued',
  message TEXT,
  request_payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  result JSONB,
  error JSONB,
  progress JSONB NOT NULL DEFAULT '{}'::jsonb,
  total_companies INTEGER NOT NULL DEFAULT 0,
  campaign_companies_materialized INTEGER NOT NULL DEFAULT 0,
  companies_processing INTEGER NOT NULL DEFAULT 0,
  companies_pending_review INTEGER NOT NULL DEFAULT 0,
  companies_failed INTEGER NOT NULL DEFAULT 0,
  company_verification_tasks_pending INTEGER NOT NULL DEFAULT 0,
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  failed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT campaign_start_jobs_status_check CHECK (
    status IN ('queued', 'running', 'completed', 'failed', 'cancelled')
  ),
  CONSTRAINT campaign_start_jobs_nonnegative_counts CHECK (
    total_companies >= 0
    AND campaign_companies_materialized >= 0
    AND companies_processing >= 0
    AND companies_pending_review >= 0
    AND companies_failed >= 0
    AND company_verification_tasks_pending >= 0
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_campaign_start_jobs_one_active_per_campaign
  ON public.campaign_start_jobs(organization_id, campaign_id)
  WHERE status IN ('queued', 'running');

CREATE INDEX IF NOT EXISTS idx_campaign_start_jobs_org_campaign_created
  ON public.campaign_start_jobs(organization_id, campaign_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_campaign_start_jobs_org_status_created
  ON public.campaign_start_jobs(organization_id, status, created_at DESC);

DROP TRIGGER IF EXISTS update_campaign_start_jobs_updated_at ON public.campaign_start_jobs;
CREATE TRIGGER update_campaign_start_jobs_updated_at
  BEFORE UPDATE ON public.campaign_start_jobs
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

ALTER TABLE public.campaign_start_jobs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS campaign_start_jobs_select_org ON public.campaign_start_jobs;
CREATE POLICY campaign_start_jobs_select_org
  ON public.campaign_start_jobs
  FOR SELECT
  USING (organization_id = (auth.jwt() ->> 'org_id'));

COMMENT ON TABLE public.campaign_start_jobs IS 'Durable state for asynchronous campaign start execution, including large CRM/custom audience starts.';
COMMENT ON COLUMN public.campaign_start_jobs.status IS 'Lifecycle status: queued, running, completed, failed, or cancelled.';
COMMENT ON COLUMN public.campaign_start_jobs.phase IS 'Human-readable execution phase such as queued, validating, materializing, processing, completed, or failed.';
COMMENT ON COLUMN public.campaign_start_jobs.progress IS 'Additional progress details computed by Modal, for example status counts by company processing_status.';
COMMENT ON COLUMN public.campaign_start_jobs.company_verification_tasks_pending IS 'Pending company_verification tasks for this campaign at the last progress refresh.';
