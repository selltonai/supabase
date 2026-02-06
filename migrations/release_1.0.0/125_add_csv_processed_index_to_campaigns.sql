-- Migration: Add csv_processed_index column to campaigns
-- Description: Stores processed CSV row identifiers as a text array for each campaign
-- Author: System
-- Date: 2025-01-21

-- Add column to campaigns to track processed CSV IDs
ALTER TABLE campaigns
  ADD COLUMN IF NOT EXISTS csv_processed_index TEXT[] DEFAULT '{}';

-- Create a GIN index for efficient searching/filtering within the array
CREATE INDEX IF NOT EXISTS idx_campaigns_csv_processed_index
  ON campaigns USING GIN (csv_processed_index);

-- Add documentation comment
COMMENT ON COLUMN campaigns.csv_processed_index IS 'List of processed CSV row identifiers for this campaign';





