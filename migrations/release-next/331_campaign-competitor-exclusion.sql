-- Add campaign-level competitor outreach control and company competitor classification.
--
-- Projects depending on this:
-- - selltonai writes campaigns.allow_competitor_outreach from campaign setup/edit flows.
-- - selltonai-modal reads the flag before task creation and writes companies.is_competitor metadata.
--
-- Application compatibility:
-- - Safe/idempotent. Defaults preserve existing behavior by excluding detected competitors.

ALTER TABLE public.campaigns
  ADD COLUMN IF NOT EXISTS allow_competitor_outreach boolean NOT NULL DEFAULT false;

ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS is_competitor boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS competitor_detected_at timestamptz,
  ADD COLUMN IF NOT EXISTS competitor_detection_source text,
  ADD COLUMN IF NOT EXISTS competitor_detection_reason text,
  ADD COLUMN IF NOT EXISTS competitor_detection_confidence numeric(4,3),
  ADD COLUMN IF NOT EXISTS competitor_blocked_by_campaign_id uuid REFERENCES public.campaigns(id) ON DELETE SET NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'companies_competitor_detection_confidence_chk'
      AND conrelid = 'public.companies'::regclass
  ) THEN
    ALTER TABLE public.companies
      ADD CONSTRAINT companies_competitor_detection_confidence_chk
      CHECK (
        competitor_detection_confidence IS NULL
        OR (
          competitor_detection_confidence >= 0
          AND competitor_detection_confidence <= 1
        )
      );
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_campaigns_allow_competitor_outreach
  ON public.campaigns(organization_id, allow_competitor_outreach)
  WHERE allow_competitor_outreach = true;

CREATE INDEX IF NOT EXISTS idx_companies_org_competitor
  ON public.companies(organization_id, is_competitor)
  WHERE is_competitor = true;

CREATE INDEX IF NOT EXISTS idx_companies_competitor_requeue
  ON public.companies(organization_id, processing_status, is_competitor)
  WHERE is_competitor = true;

COMMENT ON COLUMN public.campaigns.allow_competitor_outreach IS
  'When false, companies detected as competitors are marked and skipped before outreach task creation. When true, marked competitors may be processed.';

COMMENT ON COLUMN public.companies.is_competitor IS
  'True when ICP/company-fit analysis classified the company as a direct or indirect competitor for campaign outreach.';

COMMENT ON COLUMN public.companies.competitor_detected_at IS
  'Timestamp when the company was last classified as a competitor.';

COMMENT ON COLUMN public.companies.competitor_detection_source IS
  'Source of competitor classification, such as icp_scoring_ai or campaign_cron_gate.';

COMMENT ON COLUMN public.companies.competitor_detection_reason IS
  'Short human-readable reason returned by the classifier for competitor classification.';

COMMENT ON COLUMN public.companies.competitor_detection_confidence IS
  'Classifier confidence from 0 to 1 for competitor classification.';

COMMENT ON COLUMN public.companies.competitor_blocked_by_campaign_id IS
  'Campaign that most recently blocked this competitor from outreach because allow_competitor_outreach was false.';

NOTIFY pgrst, 'reload schema';
