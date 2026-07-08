-- Force competitor exclusion for all campaigns.
--
-- Projects depending on this:
-- - selltonai always writes campaigns.allow_competitor_outreach=false.
-- - selltonai-modal ignores true values and always skips detected competitors.
--
-- Application compatibility:
-- - Safe/idempotent. Existing true values are flipped to false.
-- - The column remains for compatibility with deployed code and old rows.

UPDATE public.campaigns
SET allow_competitor_outreach = false
WHERE allow_competitor_outreach IS DISTINCT FROM false;

ALTER TABLE public.campaigns
  ALTER COLUMN allow_competitor_outreach SET DEFAULT false;

DROP INDEX IF EXISTS public.idx_campaigns_allow_competitor_outreach;

COMMENT ON COLUMN public.campaigns.allow_competitor_outreach IS
  'Deprecated compatibility flag. Competitor exclusion is always active; detected competitors are marked and skipped before outreach task creation.';

NOTIFY pgrst, 'reload schema';
