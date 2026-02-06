-- Migration: Add industries column to organization_files table
-- Purpose: Allow case studies to be tagged with industries for better filtering and matching
-- Date: 2025-11-23

-- Add industries column to organization_files table
-- This will be an array of industry codes (e.g., ['manufacturing', 'it_services_and_it_consulting'])
-- Empty array means the case study can be used for all industries
ALTER TABLE organization_files
  ADD COLUMN IF NOT EXISTS industries text[] DEFAULT '{}'::text[];

-- Create index for efficient industry filtering
CREATE INDEX IF NOT EXISTS idx_organization_files_industries 
  ON organization_files USING GIN(industries)
  WHERE file_category = 'case_study';

-- Add comment
COMMENT ON COLUMN organization_files.industries IS 'Array of industry codes that this case study is relevant for. Empty array means applicable to all industries. Only used for case_study file category.';

