-- Manual Script: Remove Datastore Table
-- Description: Removes the datastore table and all its related functions, indexes, and dependencies
--              This table was used for vector embeddings and content search
-- 
-- IMPORTANT: Run this script in your Supabase SQL Editor or database console
-- 
-- Components being removed:
-- - datastore table
-- - search_similar_content functions
-- - All related indexes and constraints
-- 
-- The pgvector extension will remain as it might be used by other tables

-- Step 1: Drop the search functions that depend on the datastore table
DROP FUNCTION IF EXISTS search_similar_content(vector, text, float, int);
DROP FUNCTION IF EXISTS search_similar_content_text(vector, text, float, int);
DROP FUNCTION IF EXISTS search_similar_content_uuid(vector, uuid, float, int);

-- Step 2: Drop the datastore table (this will also drop all indexes and constraints)
DROP TABLE IF EXISTS datastore CASCADE;

-- Verification: Check that the table is removed
-- You can run this query to verify the table is gone:
-- SELECT table_name FROM information_schema.tables WHERE table_name = 'datastore';

-- Note: If you want to remove the pgvector extension completely (only if no other tables use it):
-- DROP EXTENSION IF EXISTS vector CASCADE; 