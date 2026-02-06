-- Migration: Create organization_files_chunks table and modify organization_files
-- Description: Creates a new table for storing document chunks with embeddings and adds full_text and pages_count to organization_files
-- 
-- Note: The table name 'organization_files_chunks' was chosen over 'organization_files_parts' 
-- for alignment with NLP terminology, as 'chunks' clearly indicates text segments used for 
-- embedding and semantic search operations.

-- Enable pgvector extension for vector embeddings
CREATE EXTENSION IF NOT EXISTS vector;

-- Create organization_files_chunks table
CREATE TABLE IF NOT EXISTS public.organization_files_chunks (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id text NOT NULL,
  file_id uuid,
  chunk_text text NOT NULL,
  chunk_embedding vector,
  metadata jsonb DEFAULT '{}'::jsonb,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT organization_files_chunks_pkey PRIMARY KEY (id),
  CONSTRAINT organization_files_chunks_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id) ON DELETE CASCADE,
  CONSTRAINT organization_files_chunks_file_id_fkey FOREIGN KEY (file_id) REFERENCES public.organization_files(id) ON DELETE CASCADE
);

-- Add indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_organization_files_chunks_organization_id ON public.organization_files_chunks(organization_id);
CREATE INDEX IF NOT EXISTS idx_organization_files_chunks_file_id ON public.organization_files_chunks(file_id);
CREATE INDEX IF NOT EXISTS idx_organization_files_chunks_created_at ON public.organization_files_chunks(created_at);

-- Modify organization_files table to add new columns
ALTER TABLE public.organization_files
  ADD COLUMN IF NOT EXISTS full_text text,
  ADD COLUMN IF NOT EXISTS pages_count integer DEFAULT 0;

-- Add comments for documentation
COMMENT ON TABLE public.organization_files_chunks IS 'Stores text chunks and their embeddings for documents, linked to organizations and optionally specific files. Used for semantic search and RAG operations.';
COMMENT ON COLUMN public.organization_files_chunks.id IS 'Unique identifier for the chunk';
COMMENT ON COLUMN public.organization_files_chunks.organization_id IS 'Reference to the organization that owns this chunk';
COMMENT ON COLUMN public.organization_files_chunks.file_id IS 'Optional reference to the specific file this chunk belongs to';
COMMENT ON COLUMN public.organization_files_chunks.chunk_text IS 'The actual text content of the chunk';
COMMENT ON COLUMN public.organization_files_chunks.chunk_embedding IS 'Vector embedding representation of the chunk text for semantic search';
COMMENT ON COLUMN public.organization_files_chunks.metadata IS 'Additional metadata about the chunk (source, chunk_index, etc.)';
COMMENT ON COLUMN public.organization_files_chunks.created_at IS 'Timestamp when the chunk was created';
COMMENT ON COLUMN public.organization_files_chunks.updated_at IS 'Timestamp when the chunk was last updated';

COMMENT ON COLUMN public.organization_files.full_text IS 'The complete text content extracted from the document';
COMMENT ON COLUMN public.organization_files.pages_count IS 'The total number of pages in the document (0 for non-paginated content)';

-- Enable Row Level Security (RLS) for the new table
ALTER TABLE public.organization_files_chunks ENABLE ROW LEVEL SECURITY;

-- Create RLS policy for organization_files_chunks
-- For now, allow access to authenticated users (can be refined later based on actual auth structure)
CREATE POLICY "Authenticated users can access chunks" ON public.organization_files_chunks
  FOR ALL USING (auth.uid() IS NOT NULL);

-- Create trigger for updating updated_at timestamp
CREATE OR REPLACE FUNCTION public.update_organization_files_chunks_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_organization_files_chunks_updated_at
  BEFORE UPDATE ON public.organization_files_chunks
  FOR EACH ROW
  EXECUTE FUNCTION public.update_organization_files_chunks_updated_at(); 