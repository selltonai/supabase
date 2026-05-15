-- ============================================================
-- Onboarding Phase 8: first draft campaign metadata
-- Projects:
--   - selltonai: redirects to the generated campaign editor
--   - selltonai-modal: creates first draft campaign from approved V2 output
-- App changes required together:
--   - Modal /onboarding/create-first-campaign should populate these fields.
-- ============================================================

ALTER TABLE public.campaigns
  ADD COLUMN IF NOT EXISTS campaign_goal_text TEXT,
  ADD COLUMN IF NOT EXISTS campaign_goal JSONB DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS goal_extracted_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS goal_source TEXT,
  ADD COLUMN IF NOT EXISTS channel_strategy TEXT;

CREATE INDEX IF NOT EXISTS idx_campaigns_goal_source
  ON public.campaigns(organization_id, goal_source)
  WHERE goal_source IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_campaigns_onboarding_first_draft
  ON public.campaigns(organization_id, created_at DESC)
  WHERE goal_source = 'onboarding_auto';

COMMENT ON COLUMN public.campaigns.campaign_goal_text IS 'Natural-language campaign goal narrative. Onboarding auto-drafts this from V2 output.';
COMMENT ON COLUMN public.campaigns.campaign_goal IS 'Structured campaign goal extracted from campaign_goal_text.';
COMMENT ON COLUMN public.campaigns.goal_source IS 'Source of the campaign goal, e.g. onboarding_auto or manual.';
COMMENT ON COLUMN public.campaigns.channel_strategy IS 'Preferred channel sequence strategy, e.g. linkedin_first_email_fallback.';
