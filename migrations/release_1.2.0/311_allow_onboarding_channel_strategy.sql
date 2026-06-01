-- ============================================================
-- Onboarding Phase 8: allow onboarding first-draft channel strategy
-- Projects:
--   - selltonai: displays and launches onboarding-generated campaigns
--   - selltonai-modal: inserts onboarding first draft campaigns
-- App changes required together:
--   - Code that validates or branches on campaigns.channel_strategy must
--     accept linkedin_first_email_fallback.
-- ============================================================

ALTER TABLE public.campaigns
  ADD COLUMN IF NOT EXISTS channel_strategy TEXT;

ALTER TABLE public.campaigns
  DROP CONSTRAINT IF EXISTS campaigns_channel_strategy_check;

ALTER TABLE public.campaigns
  ADD CONSTRAINT campaigns_channel_strategy_check
  CHECK (
    channel_strategy IS NULL
    OR channel_strategy IN (
      'linkedin',
      'email',
      'mixed',
      'multi-channel',
      'linkedin_first_email_fallback'
    )
  );

COMMENT ON COLUMN public.campaigns.channel_strategy IS
  'Preferred campaign channel strategy. NULL is treated as email. Onboarding first drafts may use linkedin_first_email_fallback.';

COMMENT ON CONSTRAINT campaigns_channel_strategy_check ON public.campaigns IS
  'Allowed campaign channel strategies, including onboarding generated linkedin_first_email_fallback.';

CREATE INDEX IF NOT EXISTS idx_campaigns_channel_strategy_onboarding
  ON public.campaigns(organization_id)
  WHERE channel_strategy = 'linkedin_first_email_fallback';

NOTIFY pgrst, 'reload schema';
