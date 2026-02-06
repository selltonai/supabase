-- Complete Organization Files and Chunks Migration
-- Run this single file to set up everything in the correct order
-- Based on the working datastore pattern

-- Ensure pgvector extension is available (exactly like datastore)
CREATE EXTENSION IF NOT EXISTS vector;

-- Step 1: Create organization_files table if it doesn't exist
CREATE TABLE IF NOT EXISTS public.organization_files (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id text NOT NULL,
  file_name text NOT NULL,
  file_type text,
  file_size integer,
  file_url text,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT organization_files_pkey PRIMARY KEY (id),
  CONSTRAINT organization_files_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id) ON DELETE CASCADE
);

-- Add new columns to organization_files table if they don't exist
ALTER TABLE public.organization_files
  ADD COLUMN IF NOT EXISTS full_text text,
  ADD COLUMN IF NOT EXISTS pages_count integer DEFAULT 0,
  ADD COLUMN IF NOT EXISTS status text DEFAULT 'uploaded';

-- Step 2: Create organization_files_chunks table with proper vector dimensions (exactly like datastore)
CREATE TABLE IF NOT EXISTS public.organization_files_chunks (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id text NOT NULL,
  file_id uuid,
  chunk_text text NOT NULL,
  embedding vector(1536),  -- Following datastore pattern: vector(1536)
  metadata jsonb DEFAULT '{}'::jsonb,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT organization_files_chunks_pkey PRIMARY KEY (id),
  CONSTRAINT organization_files_chunks_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES public.organization(id) ON DELETE CASCADE,
  CONSTRAINT organization_files_chunks_file_id_fkey FOREIGN KEY (file_id) REFERENCES public.organization_files(id) ON DELETE CASCADE
);

-- Step 3: Create indexes (following datastore pattern exactly)
-- Organization files indexes
CREATE INDEX IF NOT EXISTS idx_organization_files_organization_id ON public.organization_files(organization_id);
CREATE INDEX IF NOT EXISTS idx_organization_files_status ON public.organization_files(status);
CREATE INDEX IF NOT EXISTS idx_organization_files_created_at ON public.organization_files(created_at);

-- Chunks basic indexes
CREATE INDEX IF NOT EXISTS idx_organization_files_chunks_organization_id ON public.organization_files_chunks(organization_id);
CREATE INDEX IF NOT EXISTS idx_organization_files_chunks_file_id ON public.organization_files_chunks(file_id);
CREATE INDEX IF NOT EXISTS idx_organization_files_chunks_created_at ON public.organization_files_chunks(created_at);

-- Vector index for similarity search (following datastore pattern exactly)
CREATE INDEX IF NOT EXISTS organization_files_chunks_embedding_idx 
ON organization_files_chunks 
USING ivfflat (embedding vector_l2_ops) 
WITH (lists = 100);

-- Text search index
CREATE INDEX IF NOT EXISTS idx_organization_files_chunks_text_search 
ON organization_files_chunks 
USING gin(to_tsvector('english', chunk_text));

-- Step 4: Drop existing functions first to avoid conflicts (following datastore pattern)
DROP FUNCTION IF EXISTS match_chunks(vector, text, float, int);
DROP FUNCTION IF EXISTS hybrid_search_chunks(text, vector, text, float, float, float, int);
DROP FUNCTION IF EXISTS find_similar_chunks(uuid, text, float, int);

-- Step 5: Create search functions (adapted from datastore pattern)
CREATE OR REPLACE FUNCTION match_chunks(
  query_embedding vector,
  match_organization_id text,
  similarity_threshold float DEFAULT 0.7,
  max_results int DEFAULT 10
)
RETURNS TABLE (
  id uuid,
  organization_id text,
  file_id uuid,
  chunk_text text,
  embedding vector,
  metadata jsonb,
  created_at timestamp with time zone,
  updated_at timestamp with time zone,
  similarity float
)
LANGUAGE plpgsql
AS $$
BEGIN
    -- Using cosine similarity like datastore (1 - cosine distance)
    RETURN QUERY
    SELECT
        ofc.id,
        ofc.organization_id,
        ofc.file_id,
        ofc.chunk_text,
        ofc.embedding,
        ofc.metadata,
        ofc.created_at,
        ofc.updated_at,
        1 - (ofc.embedding <=> query_embedding) AS similarity
    FROM
        organization_files_chunks ofc
    WHERE
        ofc.organization_id = match_organization_id
        AND ofc.embedding IS NOT NULL
        AND 1 - (ofc.embedding <=> query_embedding) > similarity_threshold
    ORDER BY
        ofc.embedding <=> query_embedding
    LIMIT max_results;
END;
$$;

CREATE OR REPLACE FUNCTION hybrid_search_chunks(
  query_text text,
  query_embedding vector,
  match_organization_id text,
  text_weight float DEFAULT 0.3,
  vector_weight float DEFAULT 0.7,
  match_threshold float DEFAULT 0.2,
  max_results int DEFAULT 10
)
RETURNS TABLE (
  id uuid,
  organization_id text,
  file_id uuid,
  chunk_text text,
  embedding vector,
  metadata jsonb,
  created_at timestamp with time zone,
  updated_at timestamp with time zone,
  text_rank float,
  vector_similarity float,
  combined_score float
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    WITH text_search AS (
        SELECT 
            ofc.*,
            ts_rank_cd(to_tsvector('english', ofc.chunk_text), plainto_tsquery('english', query_text)) AS text_rank
        FROM organization_files_chunks ofc
        WHERE 
            ofc.organization_id = match_organization_id
            AND to_tsvector('english', ofc.chunk_text) @@ plainto_tsquery('english', query_text)
    ),
    vector_search AS (
        SELECT 
            ofc.*,
            1 - (ofc.embedding <=> query_embedding) AS vector_similarity
        FROM organization_files_chunks ofc
        WHERE 
            ofc.organization_id = match_organization_id
            AND ofc.embedding IS NOT NULL
    )
    SELECT 
        COALESCE(ts.id, vs.id) as id,
        COALESCE(ts.organization_id, vs.organization_id) as organization_id,
        COALESCE(ts.file_id, vs.file_id) as file_id,
        COALESCE(ts.chunk_text, vs.chunk_text) as chunk_text,
        COALESCE(ts.embedding, vs.embedding) as embedding,
        COALESCE(ts.metadata, vs.metadata) as metadata,
        COALESCE(ts.created_at, vs.created_at) as created_at,
        COALESCE(ts.updated_at, vs.updated_at) as updated_at,
        COALESCE(ts.text_rank, 0.0) as text_rank,
        COALESCE(vs.vector_similarity, 0.0) as vector_similarity,
        (text_weight * COALESCE(ts.text_rank, 0.0) + vector_weight * COALESCE(vs.vector_similarity, 0.0)) as combined_score
    FROM text_search ts
    FULL OUTER JOIN vector_search vs ON ts.id = vs.id
    WHERE (text_weight * COALESCE(ts.text_rank, 0.0) + vector_weight * COALESCE(vs.vector_similarity, 0.0)) > match_threshold
    ORDER BY combined_score DESC
    LIMIT max_results;
END;
$$;

CREATE OR REPLACE FUNCTION find_similar_chunks(
  source_chunk_id uuid,
  match_organization_id text,
  similarity_threshold float DEFAULT 0.7,
  max_results int DEFAULT 5
)
RETURNS TABLE (
  id uuid,
  organization_id text,
  file_id uuid,
  chunk_text text,
  embedding vector,
  metadata jsonb,
  created_at timestamp with time zone,
  updated_at timestamp with time zone,
  similarity float
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    WITH source_chunk AS (
        SELECT embedding 
        FROM organization_files_chunks 
        WHERE id = source_chunk_id AND embedding IS NOT NULL
    )
    SELECT
        ofc.id,
        ofc.organization_id,
        ofc.file_id,
        ofc.chunk_text,
        ofc.embedding,
        ofc.metadata,
        ofc.created_at,
        ofc.updated_at,
        1 - (ofc.embedding <=> sc.embedding) AS similarity
    FROM organization_files_chunks ofc, source_chunk sc
    WHERE 
        ofc.organization_id = match_organization_id
        AND ofc.id != source_chunk_id
        AND ofc.embedding IS NOT NULL
        AND 1 - (ofc.embedding <=> sc.embedding) > similarity_threshold
    ORDER BY ofc.embedding <=> sc.embedding
    LIMIT max_results;
END;
$$;

-- Step 6: Enable RLS (following datastore pattern)
ALTER TABLE public.organization_files ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organization_files_chunks ENABLE ROW LEVEL SECURITY;

-- Create RLS policies (adjust based on your auth setup)
DROP POLICY IF EXISTS "Allow all operations on organization_files" ON public.organization_files;
DROP POLICY IF EXISTS "Allow all operations on organization_files_chunks" ON public.organization_files_chunks;

CREATE POLICY "Allow all operations on organization_files" ON public.organization_files FOR ALL USING (true);
CREATE POLICY "Allow all operations on organization_files_chunks" ON public.organization_files_chunks FOR ALL USING (true);

-- Step 7: Create trigger functions for updating updated_at timestamps
CREATE OR REPLACE FUNCTION public.update_organization_files_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.update_organization_files_chunks_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create triggers for updating updated_at timestamps
DROP TRIGGER IF EXISTS update_organization_files_updated_at ON public.organization_files;
DROP TRIGGER IF EXISTS update_organization_files_chunks_updated_at ON public.organization_files_chunks;

CREATE TRIGGER update_organization_files_updated_at
  BEFORE UPDATE ON public.organization_files
  FOR EACH ROW
  EXECUTE FUNCTION public.update_organization_files_updated_at();

CREATE TRIGGER update_organization_files_chunks_updated_at
  BEFORE UPDATE ON public.organization_files_chunks
  FOR EACH ROW
  EXECUTE FUNCTION public.update_organization_files_chunks_updated_at();

-- Step 8: Grant permissions (following datastore pattern)
GRANT ALL ON public.organization_files TO service_role;
GRANT ALL ON public.organization_files_chunks TO service_role;
GRANT EXECUTE ON FUNCTION match_chunks(vector, text, float, int) TO service_role;
GRANT EXECUTE ON FUNCTION hybrid_search_chunks(text, vector, text, float, float, float, int) TO service_role;
GRANT EXECUTE ON FUNCTION find_similar_chunks(uuid, text, float, int) TO service_role;

-- Also grant to authenticated users (adjust as needed)
GRANT EXECUTE ON FUNCTION match_chunks(vector, text, float, int) TO authenticated;
GRANT EXECUTE ON FUNCTION hybrid_search_chunks(text, vector, text, float, float, float, int) TO authenticated;
GRANT EXECUTE ON FUNCTION find_similar_chunks(uuid, text, float, int) TO authenticated;

-- Step 9: Add comments for documentation
COMMENT ON TABLE public.organization_files IS 'Stores file metadata and content for organizations, including extracted text and page counts';
COMMENT ON TABLE public.organization_files_chunks IS 'Stores text chunks and their embeddings for documents, used for semantic search and RAG operations';
COMMENT ON COLUMN public.organization_files_chunks.embedding IS 'Vector embedding representation of the chunk text for semantic search (1536 dimensions for OpenAI ada-002)';
COMMENT ON FUNCTION match_chunks IS 'Search for similar content chunks using cosine similarity within an organization';
COMMENT ON FUNCTION hybrid_search_chunks IS 'Combines full-text search and vector similarity search with weighted scoring';
COMMENT ON FUNCTION find_similar_chunks IS 'Finds chunks similar to a given source chunk within the same organization';

-- Success message
DO $$
BEGIN
    RAISE NOTICE 'Organization files and chunks migration completed successfully!';
    RAISE NOTICE 'Tables created: organization_files, organization_files_chunks';
    RAISE NOTICE 'Functions created: match_chunks, hybrid_search_chunks, find_similar_chunks';
    RAISE NOTICE 'Vector column: embedding vector(1536) with proper indexes';
END $$; 