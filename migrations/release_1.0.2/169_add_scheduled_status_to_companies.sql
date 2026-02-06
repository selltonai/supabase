-- Migration: Add 'scheduled' status to companies processing_status
-- Purpose: Allow companies to be marked as 'scheduled' for batch processing
-- Date: 2025-11-22

-- Update CHECK constraint to include 'scheduled'
DO $$
BEGIN
  -- Drop the old constraint if it exists
  IF EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'companies_processing_status_check'
  ) THEN
    ALTER TABLE companies DROP CONSTRAINT companies_processing_status_check;
  END IF;

  -- Add new constraint with 'scheduled' included
  ALTER TABLE companies 
    ADD CONSTRAINT companies_processing_status_check 
    CHECK (processing_status IN ('pending', 'scheduled', 'processing', 'completed', 'failed'));
END $$;

-- Update the generated processing_simple_status column to handle 'scheduled'
-- 'scheduled' should map to 'processing' in processing_simple_status
DO $$
BEGIN
  -- Drop the existing generated column if it exists
  IF EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
      AND table_name = 'companies' 
      AND column_name = 'processing_simple_status'
  ) THEN
    ALTER TABLE companies DROP COLUMN processing_simple_status;
  END IF;

  -- Recreate with updated logic including 'scheduled'
  ALTER TABLE companies 
    ADD COLUMN processing_simple_status TEXT GENERATED ALWAYS AS (
      CASE 
        WHEN processing_status = 'completed' THEN 'processed'
        WHEN processing_status IN ('pending', 'scheduled', 'processing') THEN 'processing'
        WHEN processing_status = 'failed' THEN 'failed'
        ELSE NULL
      END
    ) STORED;
END $$;

-- Ensure index exists for filtering by status
CREATE INDEX IF NOT EXISTS idx_companies_processing_simple_status ON companies(processing_simple_status);

-- Update documentation
COMMENT ON COLUMN companies.processing_status IS 'Status of company data processing: pending (not started), scheduled (queued for processing), processing (in progress), completed (finished), failed (error occurred)';
COMMENT ON COLUMN companies.processing_simple_status IS 'Generated status derived from processing_status: processed (completed), processing (pending/scheduled/processing), failed';




