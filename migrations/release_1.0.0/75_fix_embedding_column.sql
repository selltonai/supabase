-- Fix embedding column name and ensure proper setup
-- This handles cases where the column might be named 'chunk_embedding' instead of 'embedding'

-- Ensure pgvector extension is available
CREATE EXTENSION IF NOT EXISTS vector;

DO $$
BEGIN
    -- Check if organization_files_chunks table exists
    IF EXISTS (SELECT 1 FROM information_schema.tables 
               WHERE table_schema = 'public' 
               AND table_name = 'organization_files_chunks') THEN
        
        RAISE NOTICE 'Table organization_files_chunks exists, checking column names...';
        
        -- Check if we have 'chunk_embedding' but not 'embedding'
        IF EXISTS (SELECT 1 FROM information_schema.columns 
                   WHERE table_schema = 'public' 
                   AND table_name = 'organization_files_chunks' 
                   AND column_name = 'chunk_embedding')
           AND NOT EXISTS (SELECT 1 FROM information_schema.columns 
                          WHERE table_schema = 'public' 
                          AND table_name = 'organization_files_chunks' 
                          AND column_name = 'embedding') THEN
            
            RAISE NOTICE 'Found chunk_embedding column, renaming to embedding...';
            
            -- Rename the column
            ALTER TABLE public.organization_files_chunks 
            RENAME COLUMN chunk_embedding TO embedding;
            
            RAISE NOTICE 'Successfully renamed chunk_embedding to embedding';
            
        ELSIF EXISTS (SELECT 1 FROM information_schema.columns 
                     WHERE table_schema = 'public' 
                     AND table_name = 'organization_files_chunks' 
                     AND column_name = 'embedding') THEN
            
            RAISE NOTICE 'Column embedding already exists';
            
        ELSE
            -- Neither column exists, create it
            RAISE NOTICE 'No embedding column found, creating embedding vector(1536)...';
            
            ALTER TABLE public.organization_files_chunks 
            ADD COLUMN embedding vector(1536);
            
            RAISE NOTICE 'Created embedding column';
        END IF;
        
        -- Ensure the column has proper dimensions if it exists
        DECLARE
            col_type TEXT;
        BEGIN
            SELECT data_type INTO col_type
            FROM information_schema.columns 
            WHERE table_schema = 'public' 
            AND table_name = 'organization_files_chunks' 
            AND column_name = 'embedding';
            
            IF col_type = 'USER-DEFINED' THEN
                -- Try to ensure it has proper dimensions
                BEGIN
                    -- Test if we can insert a 1536-dimension vector
                    PERFORM '[0]'::vector(1536)::text;
                    RAISE NOTICE 'Embedding column has proper vector type';
                EXCEPTION 
                    WHEN OTHERS THEN
                        RAISE NOTICE 'Embedding column may need dimension fix: %', SQLERRM;
                END;
            END IF;
        END;
        
    ELSE
        RAISE NOTICE 'Table organization_files_chunks does not exist. Run the main migration first.';
    END IF;
END $$;

-- Update the comment
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns 
               WHERE table_schema = 'public' 
               AND table_name = 'organization_files_chunks' 
               AND column_name = 'embedding') THEN
        
        COMMENT ON COLUMN public.organization_files_chunks.embedding IS 'Vector embedding representation of the chunk text for semantic search (1536 dimensions for OpenAI ada-002)';
    END IF;
END $$; 