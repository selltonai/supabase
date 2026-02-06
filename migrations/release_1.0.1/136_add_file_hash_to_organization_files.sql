-- Migration: Add file_hash column to organization_files for duplicate detection
-- Description: Adds a SHA-256 hash column to detect duplicate files and avoid re-uploading identical files
-- Date: 2025-11-03

-- Add file_hash column if it doesn't exist
ALTER TABLE public.organization_files
  ADD COLUMN IF NOT EXISTS file_hash TEXT;

-- Create index on file_hash for faster duplicate lookups
CREATE INDEX IF NOT EXISTS idx_organization_files_hash ON public.organization_files(organization_id, file_hash)
  WHERE file_hash IS NOT NULL;

-- Add comment for documentation
COMMENT ON COLUMN public.organization_files.file_hash IS 'SHA-256 hash of the file content. Used to detect duplicate files within the same organization.';

