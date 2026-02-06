-- Simple migration to update file_category_enum values
-- Run this in your Supabase SQL Editor

-- Step 1: Add new enum values to the existing enum
ALTER TYPE file_category_enum ADD VALUE IF NOT EXISTS 'transcripts';
ALTER TYPE file_category_enum ADD VALUE IF NOT EXISTS 'internal_documents'; 
ALTER TYPE file_category_enum ADD VALUE IF NOT EXISTS 'sales_papers';
ALTER TYPE file_category_enum ADD VALUE IF NOT EXISTS 'sait_guidelines';

