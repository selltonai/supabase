-- Migration: Add total_companies column to campaigns table
-- Description: Adds total_companies field to track number of companies associated with a campaign
-- Author: System
-- Date: 2025-01-16

-- Add total_companies column to campaigns table
ALTER TABLE campaigns 
  ADD COLUMN IF NOT EXISTS total_companies INTEGER DEFAULT 0;

-- Create index for performance
CREATE INDEX IF NOT EXISTS idx_campaigns_total_companies ON campaigns(total_companies);

-- Add comment for documentation
COMMENT ON COLUMN campaigns.total_companies IS 'Number of companies associated with this campaign';

-- Update existing campaigns to calculate total_companies from campaign_companies table
UPDATE campaigns 
SET total_companies = (
  SELECT COUNT(DISTINCT company_id)
  FROM campaign_companies cc
  WHERE cc.campaign_id = campaigns.id
)
WHERE EXISTS (
  SELECT 1 
  FROM campaign_companies cc 
  WHERE cc.campaign_id = campaigns.id
); 