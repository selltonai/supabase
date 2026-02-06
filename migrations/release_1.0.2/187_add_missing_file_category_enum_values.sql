-- Migration: Add missing file_category_enum values
-- Adds sales_papers, transcripts, internal_documents, sait_guidelines, and brand_guidelines to file_category_enum

-- Add missing enum values (IF NOT EXISTS prevents errors if already added)
ALTER TYPE file_category_enum ADD VALUE IF NOT EXISTS 'transcripts';
ALTER TYPE file_category_enum ADD VALUE IF NOT EXISTS 'internal_documents'; 
ALTER TYPE file_category_enum ADD VALUE IF NOT EXISTS 'sales_papers';
ALTER TYPE file_category_enum ADD VALUE IF NOT EXISTS 'sait_guidelines';
ALTER TYPE file_category_enum ADD VALUE IF NOT EXISTS 'brand_guidelines';

-- Update comment for documentation
COMMENT ON COLUMN organization_files.file_category IS 'Category of the file: documents, transcripts, internal_documents, sales_papers, sait_guidelines, brand_guidelines, case_study, sales_scripts, images, presentations, spreadsheets, proposals, other';

