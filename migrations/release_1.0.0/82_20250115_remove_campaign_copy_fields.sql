-- Migration: Remove campaign copy fields
-- Created: 2025-01-15
-- Description: Remove pre_generated_copy, subject_line, and final_copy columns from campaigns table

-- Remove the columns from campaigns table
ALTER TABLE campaigns 
DROP COLUMN IF EXISTS pre_generated_copy,
DROP COLUMN IF EXISTS subject_line,
DROP COLUMN IF EXISTS final_copy;

-- Add comment to track this change
COMMENT ON TABLE campaigns IS 'Campaign management table - removed copy fields in migration 82_20250115'; 