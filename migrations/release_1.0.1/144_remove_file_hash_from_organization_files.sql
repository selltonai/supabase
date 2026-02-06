-- Migration: Remove file_hash column from organization_files table
-- Description: Removes file_hash column and related index as it's no longer being used
-- Date: 2025-01-XX

-- Drop the index on file_hash if it exists
DROP INDEX IF EXISTS idx_organization_files_hash;

-- Remove file_hash column from organization_files table if it exists
ALTER TABLE public.organization_files
  DROP COLUMN IF EXISTS file_hash;

-- Update comment to reflect removal of file_hash
COMMENT ON TABLE public.organization_files IS 'Stores metadata and full text content for uploaded documents. Used for AI training and email generation.';

