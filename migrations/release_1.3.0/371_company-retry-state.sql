-- Owners: selltonai-modal (writer). Consumers: selltonai (reads for display).
-- Company processing / contact-extraction retry state.
--
-- Before this, a failed company was either abandoned silently or re-run on
-- every cron tick with no limit (and the sweepers overwrote the reason).
-- selltonai-modal's company_retry_policy now counts failed attempts, waits a
-- growing interval between them (next_retry_at) and stops after 7 attempts
-- with the reason left in failure_reason / processing_error.
--
-- Apply BEFORE deploying the Modal and selltonai releases that read these
-- columns: the Modal crons filter on next_retry_at and the BFF selects both.
--
-- Additive and idempotent. The same file ships on main (release_1.3.0/371)
-- and stage (next-release/378); applying it twice is a no-op.
-- Safe to drop: ALTER TABLE public.companies DROP COLUMN IF EXISTS retry_attempts,
--   DROP COLUMN IF EXISTS next_retry_at;

ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS retry_attempts integer NOT NULL DEFAULT 0;

ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS next_retry_at timestamptz;

COMMENT ON COLUMN public.companies.retry_attempts IS
  'Failed processing / contact-extraction attempts since the last success (selltonai-modal company_retry_policy). Reset to 0 on success and when the company is reset for a new campaign.';

COMMENT ON COLUMN public.companies.next_retry_at IS
  'Earliest time the crons may retry this company after a transient failure. NULL = no wait pending.';

-- Verify:
-- SELECT column_name, data_type, is_nullable, column_default
-- FROM information_schema.columns
-- WHERE table_schema = 'public' AND table_name = 'companies'
--   AND column_name IN ('retry_attempts', 'next_retry_at');
