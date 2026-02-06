-- Update file_category_enum to use new document categories
-- Step 1: Create new enum with updated values
CREATE TYPE file_category_enum_new AS ENUM (
  'documents',
  'transcripts', 
  'internal_documents',
  'sales_papers',
  'sait_guidelines',
  'brand_guidelines'
);

-- Step 2: Drop the existing default value first
ALTER TABLE organization_files 
ALTER COLUMN file_category DROP DEFAULT;

-- Step 3: Update the column to use the new enum type
ALTER TABLE organization_files 
ALTER COLUMN file_category TYPE file_category_enum_new USING 
  CASE 
    WHEN file_category::text = 'external' THEN 'documents'::file_category_enum_new
    WHEN file_category::text = 'case_study' THEN 'documents'::file_category_enum_new
    WHEN file_category::text = 'interview_transcripts' THEN 'transcripts'::file_category_enum_new
    WHEN file_category::text = 'internal' THEN 'internal_documents'::file_category_enum_new
    WHEN file_category::text = 'sales_scripts' THEN 'sales_papers'::file_category_enum_new
    WHEN file_category::text = 'brand_guidelines' THEN 'brand_guidelines'::file_category_enum_new
    WHEN file_category::text = 'documents' THEN 'documents'::file_category_enum_new
    ELSE 'documents'::file_category_enum_new
  END;

-- Step 4: Drop the old enum and rename the new one
DROP TYPE file_category_enum;
ALTER TYPE file_category_enum_new RENAME TO file_category_enum;

-- Step 5: Set default value to 'documents' for new records
ALTER TABLE organization_files
ALTER COLUMN file_category SET DEFAULT 'documents';

-- Update the comment for documentation
COMMENT ON COLUMN organization_files.file_category IS 'Category of the file: documents, transcripts, internal_documents, sales_papers, sait_guidelines, brand_guidelines'; 