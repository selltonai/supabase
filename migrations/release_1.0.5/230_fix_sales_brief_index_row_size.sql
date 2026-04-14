-- Migration: 236_fix_sales_brief_index_row_size
-- Date: 2026-04-14
-- Description: Fix index row size error for sales_brief column
-- Problem: GIN index on JSONB sales_brief fails when content exceeds ~2700 bytes
-- Solution: Replace GIN index with hash index on MD5 hash (supports any size)
-- Impact: No breaking changes - sales_brief is only stored/retrieved as string, never queried with JSONB operators

-- Step 1: Drop existing GIN index on companies.sales_brief
DROP INDEX IF EXISTS idx_companies_sales_brief;

-- Step 2: Create hash-based index using MD5 hash
-- This handles any size content without row size limits
CREATE INDEX idx_companies_sales_brief_hash 
ON public.companies USING hash (md5(sales_brief::text));

-- Step 3: Apply same fix for contacts table (same column, same issue)
DROP INDEX IF EXISTS idx_contacts_sales_brief;

CREATE INDEX idx_contacts_sales_brief_hash 
ON public.contacts USING hash (md5(sales_brief::text));

-- Step 4: Fix legacy data - companies with NULL sales_brief that may have failed to save
-- These are companies where deep_research_v2 exists but sales_brief is NULL
-- The sales brief was generated but failed to save due to index error
-- Re-running the process will now succeed due to the new index
