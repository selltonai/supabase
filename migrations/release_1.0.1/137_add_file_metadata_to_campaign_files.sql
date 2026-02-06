-- Migration: Add file metadata columns to campaign_files table
-- Description: Allows campaign_files to store file metadata directly instead of referencing organization_files
-- This separates campaign-specific documents from the general knowledge base
-- Date: 2025-11-03

-- Add file metadata columns to campaign_files table
ALTER TABLE public.campaign_files
  ADD COLUMN IF NOT EXISTS file_name TEXT,
  ADD COLUMN IF NOT EXISTS file_type TEXT,
  ADD COLUMN IF NOT EXISTS file_url TEXT,
  ADD COLUMN IF NOT EXISTS file_size INTEGER,
  ADD COLUMN IF NOT EXISTS file_category TEXT,
  ADD COLUMN IF NOT EXISTS uploaded_by TEXT,
  ADD COLUMN IF NOT EXISTS uploaded_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();

-- Make file_id nullable since we can now store files directly
ALTER TABLE public.campaign_files
  ALTER COLUMN file_id DROP NOT NULL;

-- Add check constraint to ensure either file_id or file metadata is provided
ALTER TABLE public.campaign_files
  ADD CONSTRAINT campaign_files_file_or_metadata_check 
  CHECK (
    (file_id IS NOT NULL) OR 
    (file_name IS NOT NULL AND file_type IS NOT NULL AND file_url IS NOT NULL AND file_size IS NOT NULL)
  );

-- Update comments
COMMENT ON TABLE public.campaign_files IS 'Stores campaign-specific files. Can either reference organization_files (general knowledge base) via file_id, or store campaign-specific files directly with metadata. Campaign-specific files are NOT included in the general knowledge base.';
COMMENT ON COLUMN public.campaign_files.file_id IS 'Reference to organization_file (if file is from general knowledge base). NULL for campaign-specific files.';

