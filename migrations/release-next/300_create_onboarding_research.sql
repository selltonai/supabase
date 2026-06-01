-- ============================================================
-- Onboarding module foundation: onboarding_research
-- Projects:
--   - selltonai: reads/polls onboarding state and stores approvals
--   - selltonai-modal: writes V1/V2 research, interview merge, and cascade state
-- App changes required together:
--   - New onboarding BFF routes and Modal onboarding endpoints should use this table.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.onboarding_research (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id TEXT NOT NULL UNIQUE REFERENCES public.organization(id) ON DELETE CASCADE,
  status TEXT NOT NULL DEFAULT 'researching',
  company_website TEXT,
  initiated_by_user_id TEXT,
  initiated_by_user_email TEXT,
  regions TEXT[],
  lines_of_business TEXT[],

  -- V1 fields from autonomous research
  v1_company_overview JSONB,
  v1_value_propositions JSONB,
  v1_core_offer JSONB,
  v1_other_offers JSONB,
  v1_case_studies JSONB,
  v1_use_cases JSONB,
  v1_icp_profiles JSONB,
  v1_ideal_customers JSONB,
  v1_competitors JSONB,
  v1_partnerships JSONB,
  v1_brand_perception JSONB,
  v1_market_intelligence JSONB,
  v1_raw_sources JSONB,
  v1_confidence_scores JSONB,
  v1_research_metadata JSONB DEFAULT '{}'::jsonb,

  -- V2 fields from interview merge
  v2_brand_positioning JSONB,
  v2_icp_profiles JSONB,
  v2_case_studies JSONB,
  v2_selling_narrative JSONB,
  v2_selling_context JSONB,
  v2_direct_competitors JSONB,
  v2_use_cases JSONB,
  v2_ideal_customers JSONB,
  v2_suggested_regions JSONB,
  v2_extraction_warnings JSONB DEFAULT '[]'::jsonb,
  v2_generation_metadata JSONB DEFAULT '{}'::jsonb,

  -- Voice interview data
  interview_transcript TEXT,
  interview_audio_url TEXT,
  interview_call_id TEXT,
  interview_duration_seconds INTEGER,

  -- Approval tracking
  approved_sections JSONB NOT NULL DEFAULT '{}'::jsonb,

  error_message TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT onboarding_research_status_check CHECK (
    status IN (
      'researching',
      'v1_complete',
      'interviewing',
      'interviewing_complete',
      'v2_generating',
      'v2_complete',
      'approved',
      'failed'
    )
  )
);

CREATE INDEX IF NOT EXISTS idx_onboarding_research_org_status
  ON public.onboarding_research(organization_id, status);

CREATE INDEX IF NOT EXISTS idx_onboarding_research_status_updated
  ON public.onboarding_research(status, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_onboarding_research_created_at
  ON public.onboarding_research(created_at DESC);

CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_onboarding_research_updated_at ON public.onboarding_research;
CREATE TRIGGER update_onboarding_research_updated_at
  BEFORE UPDATE ON public.onboarding_research
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

ALTER TABLE public.onboarding_research ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS onboarding_research_select_org ON public.onboarding_research;
CREATE POLICY onboarding_research_select_org
  ON public.onboarding_research
  FOR SELECT
  USING (organization_id = (auth.jwt() ->> 'org_id'));

COMMENT ON TABLE public.onboarding_research IS 'Persistent state for AI-powered onboarding V1 research, voice interview, V2 output, and approvals.';
COMMENT ON COLUMN public.onboarding_research.status IS 'Research/approval state for the autonomous onboarding pipeline.';
COMMENT ON COLUMN public.onboarding_research.initiated_by_user_id IS 'Clerk user id that started the onboarding research job.';
COMMENT ON COLUMN public.onboarding_research.initiated_by_user_email IS 'Email of the user that started the onboarding research job, used by Modal-side funnel events.';
COMMENT ON COLUMN public.onboarding_research.approved_sections IS 'JSON map of V2 section names to boolean approval state.';
