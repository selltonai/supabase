-- Migration: Add generated status columns for companies and contacts
-- Purpose: Provide a unified simple status field (processed, processing, failed)
-- while preserving existing processing_status values (pending, processing, completed, failed)
-- Date: 2025-08-09

-- Companies: ensure processing_status exists and add generated processing_simple_status column
DO $$
BEGIN
  -- Ensure processing_status exists
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' AND table_name = 'companies' AND column_name = 'processing_status'
  ) THEN
    ALTER TABLE companies ADD COLUMN processing_status TEXT DEFAULT 'pending';
  END IF;

  -- If a previous attempt created a 'status' column, rename it to processing_simple_status
  IF EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' AND table_name = 'companies' AND column_name = 'status'
  ) AND NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' AND table_name = 'companies' AND column_name = 'processing_simple_status'
  ) THEN
    ALTER TABLE companies RENAME COLUMN status TO processing_simple_status;
  END IF;

  -- Add processing_simple_status column if not exists
  IF NOT EXISTS (
    SELECT 1 
    FROM information_schema.columns 
    WHERE table_schema = 'public'
      AND table_name = 'companies'
      AND column_name = 'processing_simple_status'
  ) THEN
    ALTER TABLE companies 
      ADD COLUMN processing_simple_status TEXT GENERATED ALWAYS AS (
        CASE 
          WHEN processing_status = 'completed' THEN 'processed'
          WHEN processing_status IN ('pending', 'processing') THEN 'processing'
          WHEN processing_status = 'failed' THEN 'failed'
          ELSE NULL
        END
      ) STORED;
  END IF;
END $$;

-- Ensure index for filtering by status
CREATE INDEX IF NOT EXISTS idx_companies_processing_simple_status ON companies(processing_simple_status);

-- Contacts: ensure processing_status exists and add generated processing_simple_status column
DO $$
BEGIN
  -- Ensure processing_status exists
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' AND table_name = 'contacts' AND column_name = 'processing_status'
  ) THEN
    ALTER TABLE contacts ADD COLUMN processing_status TEXT DEFAULT 'pending';
  END IF;

  -- If a previous attempt created a 'status' column, rename it to processing_simple_status
  IF EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' AND table_name = 'contacts' AND column_name = 'status'
  ) AND NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' AND table_name = 'contacts' AND column_name = 'processing_simple_status'
  ) THEN
    ALTER TABLE contacts RENAME COLUMN status TO processing_simple_status;
  END IF;

  -- Add processing_simple_status column if not exists
  IF NOT EXISTS (
    SELECT 1 
    FROM information_schema.columns 
    WHERE table_schema = 'public'
      AND table_name = 'contacts'
      AND column_name = 'processing_simple_status'
  ) THEN
    ALTER TABLE contacts 
      ADD COLUMN processing_simple_status TEXT GENERATED ALWAYS AS (
        CASE 
          WHEN processing_status = 'completed' THEN 'processed'
          WHEN processing_status IN ('pending', 'processing') THEN 'processing'
          WHEN processing_status = 'failed' THEN 'failed'
          ELSE NULL
        END
      ) STORED;
  END IF;
END $$;

-- Ensure index for filtering by status
CREATE INDEX IF NOT EXISTS idx_contacts_processing_simple_status ON contacts(processing_simple_status);

-- Documentation
COMMENT ON COLUMN companies.processing_simple_status IS 'Generated status derived from processing_status: processed (completed), processing (pending/processing), failed';
COMMENT ON COLUMN contacts.processing_simple_status IS 'Generated status derived from processing_status: processed (completed), processing (pending/processing), failed';


