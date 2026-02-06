-- Create datastore table with minimal columns

-- Ensure pgvector extension is available
CREATE EXTENSION IF NOT EXISTS vector;

-- Create the datastore table
CREATE TABLE datastore (
    id SERIAL PRIMARY KEY,
    organization_id TEXT NOT NULL REFERENCES organization(id),  -- The organization that owns this content
    url TEXT NOT NULL,                          -- The URL of the page where the content was extracted from
    content TEXT NOT NULL,                      -- The actual text content
    embedding vector(1536)                      -- Vector embedding of the content
);

-- Create index for URL lookups
CREATE INDEX datastore_url_idx ON datastore (url);

-- Create index for organization lookups
CREATE INDEX datastore_organization_id_idx ON datastore (organization_id);

-- Create a vector index for similarity search using ivfflat (more widely available)
-- This provides fast approximate nearest neighbor search
CREATE INDEX datastore_embedding_idx ON datastore USING ivfflat (embedding vector_l2_ops) WITH (lists = 100);

-- Drop existing function first to avoid return type conflict
DROP FUNCTION IF EXISTS search_similar_content(vector, float, int);

-- Migration to fix the search_similar_content RPC function overloading issue
-- Run this in your Supabase SQL Editor

-- First, let's drop the conflicting functions
DROP FUNCTION IF EXISTS search_similar_content(vector, text, float, int);
DROP FUNCTION IF EXISTS search_similar_content(vector, uuid, float, int);
DROP FUNCTION IF EXISTS search_similar_content_text(vector, text, float, int); -- Also drop the specific text/uuid ones if they exist from previous attempts
DROP FUNCTION IF EXISTS search_similar_content_uuid(vector, uuid, float, int);

-- Migration to fix the search_similar_content RPC function overloading issue
-- AND switch to Cosine Similarity for search.
-- Run this in your Supabase SQL Editor

-- First, let's drop the conflicting functions (ensure clean slate)
DROP FUNCTION IF EXISTS search_similar_content(vector, text, float, int);
DROP FUNCTION IF EXISTS search_similar_content(vector, uuid, float, int);
DROP FUNCTION IF EXISTS search_similar_content_text(vector, text, float, int);
DROP FUNCTION IF EXISTS search_similar_content_uuid(vector, uuid, float, int);

-- Create a new function that explicitly supports text organization_id
-- Uses Cosine Similarity (<=> operator)
CREATE OR REPLACE FUNCTION search_similar_content_text(
    query_embedding vector,
    organization_id text,
    similarity_threshold float DEFAULT 0.7, -- Adjust threshold for cosine similarity (often higher, e.g., 0.7-0.8)
    max_results int DEFAULT 10
)
RETURNS TABLE (
    id INTEGER,
    url TEXT,
    content TEXT,
    similarity FLOAT
)
LANGUAGE plpgsql
AS $$
BEGIN
    -- Cosine Similarity = 1 - Cosine Distance
    RETURN QUERY
    SELECT
        d.id,
        d.url,
        d.content,
        1 - (d.embedding <=> query_embedding) AS similarity
    FROM
        datastore d
    WHERE
        d.organization_id = search_similar_content_text.organization_id
        AND 1 - (d.embedding <=> query_embedding) > similarity_threshold -- Filter based on cosine similarity
    ORDER BY
        d.embedding <=> query_embedding -- Order by cosine distance (ascending)
    LIMIT max_results;
END;
$$;

-- Create a new function that explicitly supports uuid organization_id
-- Uses Cosine Similarity (<=> operator)
CREATE OR REPLACE FUNCTION search_similar_content_uuid(
    query_embedding vector,
    organization_id uuid,
    similarity_threshold float DEFAULT 0.7, -- Adjust threshold for cosine similarity (often higher, e.g., 0.7-0.8)
    max_results int DEFAULT 10
)
RETURNS TABLE (
    id INTEGER,
    url TEXT,
    content TEXT,
    similarity FLOAT
)
LANGUAGE plpgsql
AS $$
BEGIN
    -- Cosine Similarity = 1 - Cosine Distance
    RETURN QUERY
    SELECT
        d.id,
        d.url,
        d.content,
        1 - (d.embedding <=> query_embedding) AS similarity
    FROM
        datastore d
    WHERE
        -- Compare text representation for index usage, as datastore.organization_id is TEXT
        d.organization_id = organization_id::text
        AND 1 - (d.embedding <=> query_embedding) > similarity_threshold -- Filter based on cosine similarity
    ORDER BY
        d.embedding <=> query_embedding -- Order by cosine distance (ascending)
    LIMIT max_results;
END;
$$;

-- Create a new single entry point function that determines which function to call
-- based on whether the input looks like a UUID. No changes needed here.
CREATE OR REPLACE FUNCTION search_similar_content(
    query_embedding vector,
    organization_id text,
    similarity_threshold float DEFAULT 0.7,
    max_results int DEFAULT 10
)
RETURNS TABLE (
    id INTEGER,
    url TEXT,
    content TEXT,
    similarity FLOAT
)
LANGUAGE plpgsql
AS $$
BEGIN
    -- Check if organization_id looks like a UUID
    IF organization_id ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
        RETURN QUERY SELECT * FROM search_similar_content_uuid(
            query_embedding,
            organization_id::uuid,
            similarity_threshold,
            max_results
        );
    ELSE
        RETURN QUERY SELECT * FROM search_similar_content_text(
            query_embedding,
            organization_id,
            similarity_threshold,
            max_results
        );
    END IF;
END;
$$;

-- IMPORTANT: For best performance with cosine similarity, update your HNSW index.
-- You should DROP the existing index and CREATE a new one using 'vector_cosine_ops'.
-- Example (run separately or integrate into your migration strategy):
-- DROP INDEX IF EXISTS datastore_embedding_idx; -- Or the name created by idx_datastore_embedding_vector
-- CREATE INDEX datastore_embedding_cosine_idx ON datastore USING hnsw (embedding vector_cosine_ops);

-- Note: The CREATE INDEX IF NOT EXISTS statements below might be redundant if the index
-- already exists from a previous migration. They also specify 'vector_l2_ops', which is
-- not optimal for the cosine similarity queries above.
-- Consider removing these or ensuring your primary index uses 'vector_cosine_ops'.
CREATE INDEX IF NOT EXISTS idx_datastore_organization_id ON datastore(organization_id);
-- CREATE INDEX IF NOT EXISTS idx_datastore_embedding_vector ON datastore USING hnsw (embedding vector_l2_ops); -- Remove or change this to cosine_ops

-- Grant permissions to use these functions
GRANT EXECUTE ON FUNCTION search_similar_content(vector, text, float, int) TO authenticated;
GRANT EXECUTE ON FUNCTION search_similar_content_text(vector, text, float, int) TO authenticated;
GRANT EXECUTE ON FUNCTION search_similar_content_uuid(vector, uuid, float, int) TO authenticated;
-- Review if anon access is required
GRANT EXECUTE ON FUNCTION search_similar_content(vector, text, float, int) TO anon;
GRANT EXECUTE ON FUNCTION search_similar_content_text(vector, text, float, int) TO anon;
GRANT EXECUTE ON FUNCTION search_similar_content_uuid(vector, uuid, float, int) TO anon;

COMMENT ON FUNCTION search_similar_content IS 'Search for similar content using cosine similarity. Works with both UUID and text organization IDs.'; 