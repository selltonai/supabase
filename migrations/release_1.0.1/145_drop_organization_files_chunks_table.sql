-- Migration: Drop organization_files_chunks table and all related objects
-- Description: Removes the organization_files_chunks table as we're now using Supabase vector database directly
-- Date: 2025-01-XX

-- Drop the trigger first (only if table exists)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'organization_files_chunks') THEN
        DROP TRIGGER IF EXISTS update_organization_files_chunks_updated_at ON public.organization_files_chunks;
    END IF;
END $$;

-- Drop the function used by the trigger
DROP FUNCTION IF EXISTS public.update_organization_files_chunks_updated_at();

-- Drop all indexes on organization_files_chunks (using IF EXISTS for safety)
DROP INDEX IF EXISTS idx_organization_files_chunks_organization_id;
DROP INDEX IF EXISTS idx_organization_files_chunks_file_id;
DROP INDEX IF EXISTS idx_organization_files_chunks_created_at;
DROP INDEX IF EXISTS organization_files_chunks_embedding_idx;
DROP INDEX IF EXISTS idx_organization_files_chunks_text_search;

-- Drop RLS policies (only if table exists)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'organization_files_chunks') THEN
        DROP POLICY IF EXISTS "Allow all operations on organization_files_chunks" ON public.organization_files_chunks;
        DROP POLICY IF EXISTS "Authenticated users can access chunks" ON public.organization_files_chunks;
    END IF;
END $$;

-- Drop the table (CASCADE will handle any remaining dependencies)
DROP TABLE IF EXISTS public.organization_files_chunks CASCADE;

-- Note: COMMENT ON TABLE will fail if table doesn't exist, so we skip it
-- The table is dropped, so no comment is needed

