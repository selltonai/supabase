-- Migration: Remove processing_simple_status column (no longer needed)
-- Purpose: Simplify status management by using only processing_status
-- Date: 2025-11-23
-- 
-- Rationale: 
-- We now use processing_status directly with clear values:
-- - scheduled, processing, processed, approved, cancelled, failed, blocked_by_icp
-- The generated processing_simple_status column was an unnecessary abstraction that caused confusion.

-- Drop processing_simple_status from companies table
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
      AND table_name = 'companies' 
      AND column_name = 'processing_simple_status'
  ) THEN
    -- Drop the index first
    DROP INDEX IF EXISTS idx_companies_processing_simple_status;
    
    -- Drop the column
    ALTER TABLE companies DROP COLUMN processing_simple_status;
    
    RAISE NOTICE 'Dropped processing_simple_status column from companies table';
  ELSE
    RAISE NOTICE 'processing_simple_status column does not exist in companies table';
  END IF;
END $$;

-- Drop processing_simple_status from contacts table
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
      AND table_name = 'contacts' 
      AND column_name = 'processing_simple_status'
  ) THEN
    -- Drop the index first
    DROP INDEX IF EXISTS idx_contacts_processing_simple_status;
    
    -- Drop the column
    ALTER TABLE contacts DROP COLUMN processing_simple_status;
    
    RAISE NOTICE 'Dropped processing_simple_status column from contacts table';
  ELSE
    RAISE NOTICE 'processing_simple_status column does not exist in contacts table';
  END IF;
END $$;

-- Update dashboard stats function to use processing_status instead of processing_simple_status
DROP FUNCTION IF EXISTS get_dashboard_stats(text);

CREATE OR REPLACE FUNCTION get_dashboard_stats(p_organization_id text)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  result jsonb;
BEGIN
  SELECT jsonb_build_object(
    'companies', jsonb_build_object(
      'total', count(*),
      'scheduled', count(*) FILTER (WHERE processing_status = 'scheduled'),
      'processing', count(*) FILTER (WHERE processing_status = 'processing'),
      'processed', count(*) FILTER (WHERE processing_status = 'processed'),
      'approved', count(*) FILTER (WHERE processing_status = 'approved'),
      'cancelled', count(*) FILTER (WHERE processing_status = 'cancelled'),
      'blocked_by_icp', count(*) FILTER (WHERE blocked_by_icp = true),
      'failed', count(*) FILTER (WHERE processing_status = 'failed')
    ),
    'contacts', jsonb_build_object(
      'total', (SELECT count(*) FROM contacts WHERE organization_id = p_organization_id),
      'processing', (SELECT count(*) FROM contacts WHERE organization_id = p_organization_id AND processing_status IN ('pending', 'processing')),
      'completed', (SELECT count(*) FROM contacts WHERE organization_id = p_organization_id AND processing_status = 'completed')
    )
  )
  INTO result
  FROM companies
  WHERE organization_id = p_organization_id;
  
  RETURN result;
END;
$$;

-- Update documentation for processing_status to reflect simplified usage
COMMENT ON COLUMN companies.processing_status IS 'Status of company data processing. Flow: scheduled → processing → processed → (approved OR cancelled OR blocked_by_icp). Values: pending, scheduled, processing, processed, approved, cancelled, failed, blocked_by_icp';
COMMENT ON COLUMN contacts.processing_status IS 'Status of contact data processing. Values: pending, processing, completed, failed';

