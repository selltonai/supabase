-- Migration: Add blocked_by_icp to companies table
-- Description: Adds blocked_by_icp column to companies table for easier filtering and querying
--              This complements the blocked flag in icp_score jsonb with a dedicated boolean column
-- Author: System
-- Date: 2025-11-12

-- Add blocked_by_icp column to companies table
ALTER TABLE companies 
ADD COLUMN IF NOT EXISTS blocked_by_icp BOOLEAN DEFAULT FALSE;

-- Add index for performance when querying blocked companies
CREATE INDEX IF NOT EXISTS idx_companies_blocked_by_icp 
    ON companies(blocked_by_icp) 
    WHERE blocked_by_icp = TRUE;

-- Add index for organization queries with blocked filter
CREATE INDEX IF NOT EXISTS idx_companies_org_blocked 
    ON companies(organization_id, blocked_by_icp);

-- Add comment for documentation
COMMENT ON COLUMN companies.blocked_by_icp IS 'Whether this company was blocked by ICP hard filters and should not be processed further';

-- Update existing companies where icp_score indicates blocking
-- This backfills the new column based on existing icp_score data
UPDATE companies
SET blocked_by_icp = TRUE
WHERE icp_score IS NOT NULL 
  AND (
    (icp_score->>'blocked')::boolean = TRUE 
    OR 
    (icp_score->'llm_analysis'->>'blocked')::boolean = TRUE
  )
  AND blocked_by_icp = FALSE;

-- Create a function to automatically update blocked_by_icp when icp_score changes
CREATE OR REPLACE FUNCTION update_company_blocked_status()
RETURNS TRIGGER AS $$
BEGIN
    -- Check if icp_score indicates blocking
    IF NEW.icp_score IS NOT NULL THEN
        IF (NEW.icp_score->>'blocked')::boolean = TRUE OR 
           (NEW.icp_score->'llm_analysis'->>'blocked')::boolean = TRUE THEN
            NEW.blocked_by_icp := TRUE;
        ELSE
            NEW.blocked_by_icp := FALSE;
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to automatically update blocked_by_icp when icp_score changes
DROP TRIGGER IF EXISTS update_company_blocked_status_trigger ON companies;
CREATE TRIGGER update_company_blocked_status_trigger
    BEFORE INSERT OR UPDATE OF icp_score ON companies
    FOR EACH ROW
    EXECUTE FUNCTION update_company_blocked_status();

-- Add helpful comment
COMMENT ON TRIGGER update_company_blocked_status_trigger ON companies IS 
'Automatically sets blocked_by_icp based on icp_score.blocked flag';

