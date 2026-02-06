-- Migration: Remove Datastore Table
-- Description: Removes the datastore table and all its related functions, indexes, and dependencies
--              This table was used for vector embeddings and content search
-- Author: System  
-- Date: 2025-01-09

-- Step 1: Drop the search functions that depend on the datastore table
DROP FUNCTION IF EXISTS search_similar_content(vector, text, float, int);
DROP FUNCTION IF EXISTS search_similar_content_text(vector, text, float, int);
DROP FUNCTION IF EXISTS search_similar_content_uuid(vector, uuid, float, int);

-- Step 2: Drop the datastore table (this will also drop all indexes and constraints)
DROP TABLE IF EXISTS datastore CASCADE;

-- Note: The pgvector extension will remain as it might be used by other tables
-- If you want to remove it completely, run: DROP EXTENSION IF EXISTS vector CASCADE; 