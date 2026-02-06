-- Migration: Add lookalike company tracking fields to campaigns
-- Description: Tracks how many lookalike companies were found and processed for campaigns with selected seed companies
-- Author: System
-- Date: 2025-11-18

-- Add lookalike tracking fields
ALTER TABLE campaigns 
  ADD COLUMN IF NOT EXISTS lookalike_total_found INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS lookalike_total_processed INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS lookalike_last_page INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS lookalike_total_pages INTEGER;

-- Indexes for filtering/sorting
CREATE INDEX IF NOT EXISTS idx_campaigns_lookalike_total_found ON campaigns(lookalike_total_found);
CREATE INDEX IF NOT EXISTS idx_campaigns_lookalike_total_processed ON campaigns(lookalike_total_processed);

-- Documentation comments
COMMENT ON COLUMN campaigns.lookalike_total_found IS 'Total number of lookalike companies found based on selected seed companies';
COMMENT ON COLUMN campaigns.lookalike_total_processed IS 'Total number of lookalike companies that have been processed';
COMMENT ON COLUMN campaigns.lookalike_last_page IS 'Last page number of lookalike companies fetched from B2B API';
COMMENT ON COLUMN campaigns.lookalike_total_pages IS 'Total number of pages of lookalike companies available from B2B API';







