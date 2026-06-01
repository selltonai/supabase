-- Migration: AI-Ark enrollment idempotency
-- Release: 1.1.1
-- Purpose: Track campaign/company enrollment recovery runs so AI-Ark contact
-- discovery is not triggered repeatedly for the same enrollment.

CREATE TABLE IF NOT EXISTS public.ai_ark_enrollment_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  enrollment_id text NOT NULL,
  campaign_id uuid NOT NULL REFERENCES public.campaigns(id) ON DELETE CASCADE,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  result_count integer NOT NULL DEFAULT 0 CHECK (result_count >= 0),
  status text NOT NULL DEFAULT 'running'
    CHECK (status IN ('running', 'completed', 'failed', 'skipped')),
  error_message text,
  run_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_ai_ark_runs_enrollment_company
  ON public.ai_ark_enrollment_runs (enrollment_id, company_id);

CREATE INDEX IF NOT EXISTS idx_ai_ark_runs_campaign
  ON public.ai_ark_enrollment_runs (campaign_id);

CREATE INDEX IF NOT EXISTS idx_ai_ark_runs_org_status
  ON public.ai_ark_enrollment_runs (organization_id, status);

ALTER TABLE public.ai_ark_enrollment_runs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view AI-Ark enrollment runs for their organization"
  ON public.ai_ark_enrollment_runs;

CREATE POLICY "Users can view AI-Ark enrollment runs for their organization"
  ON public.ai_ark_enrollment_runs
  FOR SELECT
  USING (organization_id = current_setting('app.current_org_id', true));

DROP POLICY IF EXISTS "Users can insert AI-Ark enrollment runs for their organization"
  ON public.ai_ark_enrollment_runs;

CREATE POLICY "Users can insert AI-Ark enrollment runs for their organization"
  ON public.ai_ark_enrollment_runs
  FOR INSERT
  WITH CHECK (organization_id = current_setting('app.current_org_id', true));

DROP POLICY IF EXISTS "Users can update AI-Ark enrollment runs for their organization"
  ON public.ai_ark_enrollment_runs;

CREATE POLICY "Users can update AI-Ark enrollment runs for their organization"
  ON public.ai_ark_enrollment_runs
  FOR UPDATE
  USING (organization_id = current_setting('app.current_org_id', true));

COMMENT ON TABLE public.ai_ark_enrollment_runs IS
  'Idempotency ledger for AI-Ark contact discovery triggered at campaign enrollment.';

COMMENT ON COLUMN public.ai_ark_enrollment_runs.enrollment_id IS
  'Stable enrollment key, typically campaign_id:company_id.';
