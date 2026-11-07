-- ============================================================
-- Add campaign lifecycle statuses for discovery vs full completion
-- Projects:
--   - selltonai-modal: writes discovery_completed after AI-Ark/company processing
--     is exhausted, then writes fully_completed after follow-up sequences drain.
--   - selltonai: displays and locks the distinct lifecycle states.
-- App changes required together:
--   - Deploy selltonai-modal and selltonai status handling with this migration.
-- Notes:
--   - Existing completed rows are preserved as legacy final-completed campaigns.
-- ============================================================

ALTER TYPE public.campaign_status ADD VALUE IF NOT EXISTS 'discovery_completed';
ALTER TYPE public.campaign_status ADD VALUE IF NOT EXISTS 'fully_completed';

COMMENT ON TYPE public.campaign_status IS
  'Campaign lifecycle: draft, active, paused, discovery_completed, completed (legacy final), fully_completed, cancelled.';
