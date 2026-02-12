-- Migration: Add company_fetch_limit column to campaigns table
-- Description: Adds a configurable limit for how many companies can be fetched per campaign.
--              When the limit is reached, the backend stops fetching new companies and
--              the frontend stops requesting them.
-- Default: 300

ALTER TABLE campaigns
ADD COLUMN IF NOT EXISTS company_fetch_limit INTEGER DEFAULT 300;

COMMENT ON COLUMN campaigns.company_fetch_limit IS 'Maximum number of companies that can be fetched/discovered for this campaign. NULL means unlimited.';
