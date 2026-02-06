-- Migration: Add B2B search fields to campaigns table
-- Description: Adds JSONB filters and pagination metrics for B2B search at the campaign level
-- Author: System
-- Date: 2025-08-08

-- Add B2B search fields to campaigns
ALTER TABLE campaigns 
  ADD COLUMN IF NOT EXISTS b2b_search_filters JSONB DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS b2b_search_page_size INTEGER,
  ADD COLUMN IF NOT EXISTS b2b_search_last_page INTEGER,
  ADD COLUMN IF NOT EXISTS b2b_search_total_pages INTEGER,
  ADD COLUMN IF NOT EXISTS b2b_search_total_elements INTEGER;

-- Optional index for JSONB filters to support key/path queries
CREATE INDEX IF NOT EXISTS idx_campaigns_b2b_search_filters ON campaigns USING GIN (b2b_search_filters);

-- Documentation comments
COMMENT ON COLUMN campaigns.b2b_search_filters IS 'Filters used for B2B search; stored as JSONB';
COMMENT ON COLUMN campaigns.b2b_search_page_size IS 'Page size used for B2B search pagination';
COMMENT ON COLUMN campaigns.b2b_search_last_page IS 'Last processed page number from the B2B search';
COMMENT ON COLUMN campaigns.b2b_search_total_pages IS 'Total number of pages reported by the B2B search';
COMMENT ON COLUMN campaigns.b2b_search_total_elements IS 'Total number of elements reported by the B2B search';


