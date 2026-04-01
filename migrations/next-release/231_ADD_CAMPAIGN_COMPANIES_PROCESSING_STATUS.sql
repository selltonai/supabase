-- Migration: Add processing_status and related columns to campaign_companies
-- Date: 2026-04-01
-- Description: Add missing columns for campaign company processing tracking

-- Add processing_status column to campaign_companies
ALTER TABLE campaign_companies 
ADD COLUMN IF NOT EXISTS processing_status text NOT NULL DEFAULT 'pending';

-- Add index for faster filtering by processing status
CREATE INDEX IF NOT EXISTS idx_campaign_companies_processing_status 
ON campaign_companies(processing_status);

-- Add index for campaign_id + processing_status combination (common query pattern)
CREATE INDEX IF NOT EXISTS idx_campaign_companies_campaign_status 
ON campaign_companies(campaign_id, processing_status);

-- Add comment for documentation
COMMENT ON COLUMN campaign_companies.processing_status IS 'Processing status: pending, queued, processing, completed, failed';
