-- Migration: Add daily company fetch limit columns to campaigns table
-- Description: Adds a configurable daily limit for how many companies can be fetched per campaign per day.
--              The cron job resets daily_fetch_count when daily_fetch_date changes (new day).
-- Default daily limit: 50

ALTER TABLE campaigns
ADD COLUMN IF NOT EXISTS daily_company_fetch_limit INTEGER DEFAULT 50;

ALTER TABLE campaigns
ADD COLUMN IF NOT EXISTS daily_fetch_count INTEGER DEFAULT 0;

ALTER TABLE campaigns
ADD COLUMN IF NOT EXISTS daily_fetch_date DATE DEFAULT CURRENT_DATE;

COMMENT ON COLUMN campaigns.daily_company_fetch_limit IS 'Maximum number of companies that can be fetched per day for this campaign. NULL means unlimited daily.';
COMMENT ON COLUMN campaigns.daily_fetch_count IS 'Number of companies fetched today. Reset to 0 when daily_fetch_date changes.';
COMMENT ON COLUMN campaigns.daily_fetch_date IS 'The date of the last fetch. Used by the cron job to detect day change and reset daily_fetch_count.';
