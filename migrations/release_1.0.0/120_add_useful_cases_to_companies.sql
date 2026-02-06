-- Migration: Add useful case file references to companies and keep them in sync on file delete
-- Description: Adds uuid[] column on companies to track useful case document IDs and a trigger
--              that removes deleted file IDs from companies.useful_case_file_ids
-- Author: System
-- Date: 2025-08-13

-- 1) Add column to companies to store referenced useful case files (organization_files.id)
ALTER TABLE companies 
  ADD COLUMN IF NOT EXISTS useful_case_file_ids uuid[] DEFAULT '{}'::uuid[];

COMMENT ON COLUMN companies.useful_case_file_ids IS 'List of organization_files IDs that are considered useful case documents for this company.';

-- 2) Index for fast lookups by contained UUID
CREATE INDEX IF NOT EXISTS idx_companies_useful_case_file_ids 
  ON companies USING GIN (useful_case_file_ids);

-- 3) Trigger function to remove deleted file IDs from all companies
CREATE OR REPLACE FUNCTION public.remove_deleted_file_from_companies()
RETURNS trigger AS $$
BEGIN
  -- Only update rows that actually contain the file id
  UPDATE companies
     SET useful_case_file_ids = array_remove(COALESCE(useful_case_file_ids, '{}'::uuid[]), OLD.id),
         updated_at = NOW()
   WHERE OLD.id = ANY(COALESCE(useful_case_file_ids, '{}'::uuid[]))
     AND (organization_id = OLD.organization_id OR organization_id IS NOT DISTINCT FROM OLD.organization_id);

  RETURN NULL; -- AFTER DELETE trigger does not modify the deleted row
END;
$$ LANGUAGE plpgsql;

-- 4) Create trigger on organization_files deletions
DROP TRIGGER IF EXISTS trg_on_file_delete_update_companies ON public.organization_files;
CREATE TRIGGER trg_on_file_delete_update_companies
AFTER DELETE ON public.organization_files
FOR EACH ROW
EXECUTE FUNCTION public.remove_deleted_file_from_companies();


