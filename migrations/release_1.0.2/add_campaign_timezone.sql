-- Migration: Add campaign_timezone column to campaigns table
-- Description: Adds timezone support for campaign execution scheduling
-- Author: System
-- Date: 2025-02-24

-- Add campaign_timezone column to campaigns table
ALTER TABLE campaigns
ADD COLUMN IF NOT EXISTS campaign_timezone TEXT DEFAULT 'UTC';

-- Add comment to document the column
COMMENT ON COLUMN campaigns.campaign_timezone IS 'Timezone for campaign execution (e.g., UTC, America/New_York). Determines when daily limits reset and when campaigns are triggered.';

-- Create index for timezone queries if needed
CREATE INDEX IF NOT EXISTS idx_campaigns_timezone ON campaigns(campaign_timezone);
