-- Migration: Add Case Study Match Column
-- Description: Adds matches_case_study column to companies table for case study matching functionality
--              This is used as a score modifier (not a signal) - indicates if company matches case studies
-- Author: System
-- Date: 2025-01-15
-- Updated: 2025-01-XX (Cleaned up - removed all other signal columns, keeping only matches_case_study)

-- ============================================================================
-- CASE STUDY MATCH COLUMN
-- ============================================================================
ALTER TABLE companies
  ADD COLUMN IF NOT EXISTS matches_case_study BOOLEAN DEFAULT FALSE;

COMMENT ON COLUMN companies.matches_case_study IS 'Whether this company matches reference case studies (used as score modifier, not a signal)';

-- ============================================================================
-- INDEX FOR PERFORMANCE
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_companies_matches_case_study 
    ON companies(matches_case_study) 
    WHERE matches_case_study = TRUE;

-- Add composite index for organization queries with case study filter
CREATE INDEX IF NOT EXISTS idx_companies_org_case_study 
    ON companies(organization_id, matches_case_study) 
    WHERE matches_case_study = TRUE;
