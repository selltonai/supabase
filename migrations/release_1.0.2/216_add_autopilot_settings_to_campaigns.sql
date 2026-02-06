-- Migration: Add Autopilot Settings to Campaigns
-- Description: Adds columns for campaign-level autopilot settings to auto-approve tasks
-- Author: System
-- Date: 2025-12-15

-- Add autopilot columns to campaigns table with sensible defaults
-- Default: autopilot DISABLED, with company verification ON, email review ON, min ICP score 70 (when enabled)
ALTER TABLE campaigns
  ADD COLUMN IF NOT EXISTS autopilot_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS autopilot_company_verification BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS autopilot_email_review BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS autopilot_min_icp_score INTEGER DEFAULT 70;

-- Add constraint for min ICP score (0-100 range, or NULL to disable)
-- Drop first if exists to make migration idempotent
ALTER TABLE campaigns DROP CONSTRAINT IF EXISTS autopilot_min_icp_score_range;
ALTER TABLE campaigns
  ADD CONSTRAINT autopilot_min_icp_score_range 
  CHECK (autopilot_min_icp_score IS NULL OR (autopilot_min_icp_score >= 0 AND autopilot_min_icp_score <= 100));

-- Add comments explaining the columns
COMMENT ON COLUMN campaigns.autopilot_enabled IS 'Master switch for autopilot mode - must be true for any auto-approval to work. Default: FALSE';
COMMENT ON COLUMN campaigns.autopilot_company_verification IS 'When true, company verification tasks are automatically approved. Default: TRUE';
COMMENT ON COLUMN campaigns.autopilot_email_review IS 'When true, email review tasks are automatically accepted and sent. Default: TRUE';
COMMENT ON COLUMN campaigns.autopilot_min_icp_score IS 'Minimum ICP score required for auto-approval (0-100). Companies below this score are auto-declined. Default: 70';

-- Create index for quick filtering of autopilot-enabled campaigns
CREATE INDEX IF NOT EXISTS idx_campaigns_autopilot_enabled ON campaigns(autopilot_enabled) WHERE autopilot_enabled = TRUE;

-- Update existing campaigns to have default autopilot settings (autopilot OFF by default)
-- This ensures all existing campaigns get the autopilot sub-settings configured, but autopilot stays OFF
UPDATE campaigns 
SET 
  autopilot_enabled = FALSE,
  autopilot_company_verification = TRUE,
  autopilot_email_review = TRUE,
  autopilot_min_icp_score = 70
WHERE autopilot_enabled IS NULL;

