-- Migration: Add Autopilot Auto-Decline Toggle
-- Description: Adds a campaign-level toggle to control whether autopilot should auto-decline
--              companies below the minimum ICP score threshold, or leave them for manual review.
-- Author: System
-- Date: 2025-12-15

ALTER TABLE campaigns
  ADD COLUMN IF NOT EXISTS autopilot_auto_decline_below_min_icp_score BOOLEAN NOT NULL DEFAULT TRUE;

COMMENT ON COLUMN campaigns.autopilot_auto_decline_below_min_icp_score
  IS 'When autopilot + company verification are enabled and a min ICP score is set: if TRUE, companies below min are auto-declined; if FALSE, they remain pending for manual review. Default: TRUE';


