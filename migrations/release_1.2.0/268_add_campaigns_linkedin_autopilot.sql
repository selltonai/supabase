-- =====================================================================
-- 255_add_campaigns_linkedin_autopilot.sql
--
-- V3 P0-G — LinkedIn autopilot fields on `campaigns`.
--
-- Mirrors the existing email-autopilot pattern
-- (autopilot_email_review + autopilot_auto_confirm_*) so the front-end
-- and the auto-approve branch in the sequence claimer can read a
-- consistent shape across channels. New fields:
--
--   autopilot_linkedin_review                  — channel-level gate
--   autopilot_auto_confirm_linkedin_invitations — type-level: invitations
--   autopilot_auto_confirm_linkedin_messages    — type-level: messages
--                                                 (1st DM + follow-ups)
--
-- All default FALSE so existing autopilot-enabled campaigns retain
-- their email-only auto-accept behavior — opt-in for LinkedIn.
--
-- Read by:
--   - src/app/api/campaigns/[id]/autopilot/route.ts        (GET/PATCH)
--   - src/app/api/internal/sequence/claim/route.ts         (auto-approve)
--   - frontend autopilot panel
--
-- Idempotent: ADD COLUMN IF NOT EXISTS so re-running this against an
-- already-migrated database is a no-op.
-- =====================================================================

ALTER TABLE public.campaigns
  ADD COLUMN IF NOT EXISTS autopilot_linkedin_review BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS autopilot_auto_confirm_linkedin_invitations BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS autopilot_auto_confirm_linkedin_messages BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN public.campaigns.autopilot_linkedin_review IS
  'V3 P0-G — channel gate. When TRUE alongside autopilot_enabled, the LinkedIn auto-approve branch in /api/internal/sequence/claim runs (subject to the per-action-type auto_confirm flags below).';

COMMENT ON COLUMN public.campaigns.autopilot_auto_confirm_linkedin_invitations IS
  'V3 P0-G — when TRUE, LinkedIn invitation actions are auto-approved + dispatched without a review task.';

COMMENT ON COLUMN public.campaigns.autopilot_auto_confirm_linkedin_messages IS
  'V3 P0-G — when TRUE, LinkedIn message actions (initial DM + follow-ups) are auto-approved + dispatched without a review task.';
