-- Migration: Add status field to campaign_companies table
-- Description: Adds a status field to track approval status of companies in campaigns
-- Author: System
-- Date: 2025-01-09

-- Add status column to campaign_companies table
ALTER TABLE campaign_companies 
ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected'));

-- Update existing records to 'approved' status (assuming current companies are approved)
UPDATE campaign_companies SET status = 'approved' WHERE status IS NULL OR status = 'pending';

-- Add index for performance
CREATE INDEX IF NOT EXISTS idx_campaign_companies_status ON campaign_companies(status);

COMMENT ON COLUMN campaign_companies.status IS 'Approval status of company in campaign: pending, approved, rejected';