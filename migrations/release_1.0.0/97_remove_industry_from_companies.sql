-- Migration: Remove industry field from companies table
-- This migration removes the industry column and its associated index

-- Drop the index first
DROP INDEX IF EXISTS idx_companies_industry;

-- Drop the industry column
ALTER TABLE companies DROP COLUMN IF EXISTS industry;

-- Optional: Add a comment explaining why this was removed
COMMENT ON TABLE companies IS 'Company information table. Industry field has been removed as it is not used in the application.'; 