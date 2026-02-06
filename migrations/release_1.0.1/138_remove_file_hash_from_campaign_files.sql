-- Migration: Remove file_hash column from campaign_files table
-- Description: Removes file_hash column and related index as it's no longer being used
-- This migration is safe to run multiple times - it checks if columns/indexes exist before dropping
-- Date: 2025-11-03

-- Drop the index on file_hash if it exists
DROP INDEX IF EXISTS public.idx_campaign_files_hash;

-- Remove file_hash column from campaign_files table if it exists
ALTER TABLE public.campaign_files
  DROP COLUMN IF EXISTS file_hash;

-- Update comment to reflect removal of file_hash
COMMENT ON TABLE public.campaign_files IS 'Stores campaign-specific files. Can either reference organization_files (general knowledge base) via file_id, or store campaign-specific files directly with metadata. Campaign-specific files are NOT included in the general knowledge base.';

