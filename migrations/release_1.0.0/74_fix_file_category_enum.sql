-- Migration: Fix file_category_enum to include missing values
-- Description: Add case_study and sales_scripts to the enum to match UI expectations
-- Date: 2025-01-30

-- Add the missing enum values
ALTER TYPE file_category_enum ADD VALUE IF NOT EXISTS 'case_study';
ALTER TYPE file_category_enum ADD VALUE IF NOT EXISTS 'sales_scripts';

-- Update the comment to reflect all available categories
COMMENT ON COLUMN organization_files.file_category IS 'Category of the file: documents, transcripts, internal_documents, sales_papers, sait_guidelines, brand_guidelines, case_study, sales_scripts'; 