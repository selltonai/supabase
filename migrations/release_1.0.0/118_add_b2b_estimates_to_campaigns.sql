-- Migration: Add B2B estimate fields to campaigns
-- Description: Stores estimated company counts from external B2B search to support UI messaging and progress (X/Y)
-- Author: System
-- Date: 2025-08-09

-- Adds fields if they don't exist yet (compliments migration 116)
ALTER TABLE campaigns 
  ADD COLUMN IF NOT EXISTS b2b_search_total_elements INTEGER,
  ADD COLUMN IF NOT EXISTS b2b_search_total_pages INTEGER,
  ADD COLUMN IF NOT EXISTS b2b_search_page_size INTEGER,
  ADD COLUMN IF NOT EXISTS b2b_search_last_page INTEGER,
  ADD COLUMN IF NOT EXISTS estimated_total_companies INTEGER; -- handy alias for UI (redundant, but convenient)

-- Indexes to filter/sort on these values if needed
CREATE INDEX IF NOT EXISTS idx_campaigns_b2b_total_elements ON campaigns(b2b_search_total_elements);
CREATE INDEX IF NOT EXISTS idx_campaigns_estimated_total_companies ON campaigns(estimated_total_companies);

-- Keep estimated_total_companies in sync for existing rows if totals already present
UPDATE campaigns
SET estimated_total_companies = COALESCE(b2b_search_total_elements, estimated_total_companies)
WHERE b2b_search_total_elements IS NOT NULL
  AND (estimated_total_companies IS NULL OR estimated_total_companies = 0);

COMMENT ON COLUMN campaigns.estimated_total_companies IS 'Cached estimate of how many companies we expect to find overall for this campaign';
COMMENT ON COLUMN campaigns.b2b_search_total_elements IS 'Total elements as reported by the external B2B search API';
COMMENT ON COLUMN campaigns.b2b_search_total_pages IS 'Total pages as reported by the external B2B search API';
COMMENT ON COLUMN campaigns.b2b_search_page_size IS 'Page size used in the external B2B search API';
COMMENT ON COLUMN campaigns.b2b_search_last_page IS 'Last page number retrieved from the external B2B search API';


