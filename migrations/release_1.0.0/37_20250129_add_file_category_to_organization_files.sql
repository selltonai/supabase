-- Add file_category column to organization_files table
ALTER TABLE organization_files
ADD COLUMN file_category TEXT;

-- Create an enum type for file categories
CREATE TYPE file_category_enum AS ENUM (
  'internal',
  'external',
  'case_study',
  'brand_guidelines',
  'interview_transcripts',
  'sales_scripts',
  'documents'
);

-- Update the column to use the enum type
ALTER TABLE organization_files
ALTER COLUMN file_category TYPE file_category_enum USING file_category::file_category_enum;

-- Set default value to 'documents' for existing records
UPDATE organization_files
SET file_category = 'documents'
WHERE file_category IS NULL;

-- Make the column NOT NULL after setting defaults
ALTER TABLE organization_files
ALTER COLUMN file_category SET NOT NULL;

-- Set default for new records
ALTER TABLE organization_files
ALTER COLUMN file_category SET DEFAULT 'documents';

-- Add comment for documentation
COMMENT ON COLUMN organization_files.file_category IS 'Category of the file for AI training context';

-- Create index for better query performance when filtering by category
CREATE INDEX idx_organization_files_category ON organization_files(file_category);

-- Update RLS policies if needed (keeping existing ones intact)
-- The existing policies should still work as they don't reference specific columns 