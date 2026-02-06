-- Migration: Add Autopilot Email Confirmation Options
-- Description: Adds campaign-level autopilot toggles for auto-confirming initial emails, follow-ups, and replies
-- Author: System
-- Date: 2025-12-16

ALTER TABLE campaigns
  ADD COLUMN IF NOT EXISTS autopilot_auto_confirm_initial_emails BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS autopilot_auto_confirm_followup_emails BOOLEAN NOT NULL DEFAULT TRUE,
  -- Default FALSE to avoid auto-sending replies unless explicitly enabled (safety)
  ADD COLUMN IF NOT EXISTS autopilot_auto_confirm_reply_emails BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN campaigns.autopilot_auto_confirm_initial_emails IS 'When true (and autopilot enabled), initial/first outbound email tasks can be auto-accepted/sent. Default: TRUE.';
COMMENT ON COLUMN campaigns.autopilot_auto_confirm_followup_emails IS 'When true (and autopilot enabled), follow-up outbound email tasks can be auto-accepted/sent. Default: TRUE.';
COMMENT ON COLUMN campaigns.autopilot_auto_confirm_reply_emails IS 'When true (and autopilot enabled), reply email tasks can be auto-accepted/sent. Default: FALSE.';








