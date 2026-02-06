-- Migration: Add ICP Blocking Tracking to Campaign Companies
-- Description: Adds fields to track if companies were blocked by ICP filters, 
--              which ICP profile was used, and when, so they can be reprocessed if profile changes
-- Author: System
-- Date: 2025-01-XX

-- Add ICP blocking tracking columns to campaign_companies table
ALTER TABLE campaign_companies 
ADD COLUMN IF NOT EXISTS blocked_by_icp BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS icp_profile_id_used UUID REFERENCES icp_profiles(id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS icp_blocked_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS icp_failed_filters JSONB DEFAULT '[]'::jsonb,
ADD COLUMN IF NOT EXISTS icp_score_when_blocked DECIMAL(5,2);

-- Add index for performance when querying blocked companies
CREATE INDEX IF NOT EXISTS idx_campaign_companies_blocked_by_icp ON campaign_companies(blocked_by_icp) WHERE blocked_by_icp = TRUE;
CREATE INDEX IF NOT EXISTS idx_campaign_companies_icp_profile_id ON campaign_companies(icp_profile_id_used);

-- Add comment for documentation
COMMENT ON COLUMN campaign_companies.blocked_by_icp IS 'Whether this company was blocked by ICP hard filters';
COMMENT ON COLUMN campaign_companies.icp_profile_id_used IS 'The ICP profile ID that was used when this company was scored/blocked';
COMMENT ON COLUMN campaign_companies.icp_blocked_at IS 'Timestamp when company was blocked by ICP filters';
COMMENT ON COLUMN campaign_companies.icp_failed_filters IS 'Array of failed hard filter reasons when blocked';
COMMENT ON COLUMN campaign_companies.icp_score_when_blocked IS 'ICP score at time of blocking (usually 0 for hard filter failures)';

-- Create a function to reset ICP blocking status for reprocessing
CREATE OR REPLACE FUNCTION reset_icp_blocking_for_profile(profile_id UUID)
RETURNS INTEGER AS $$
DECLARE
    updated_count INTEGER;
BEGIN
    UPDATE campaign_companies
    SET 
        blocked_by_icp = FALSE,
        icp_blocked_at = NULL,
        icp_failed_filters = '[]'::jsonb,
        icp_score_when_blocked = NULL,
        updated_at = NOW()
    WHERE icp_profile_id_used = profile_id
      AND blocked_by_icp = TRUE;
    
    GET DIAGNOSTICS updated_count = ROW_COUNT;
    RETURN updated_count;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION reset_icp_blocking_for_profile IS 'Resets ICP blocking status for all companies that were blocked using a specific ICP profile. Use this when an ICP profile is updated to allow reprocessing.';







