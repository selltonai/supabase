-- Migration: Add 'processed', 'cancelled', 'approved', and 'blocked_by_icp' statuses to companies processing_status
-- Purpose: Support the new status flow: scheduled -> processing -> processed -> (verification task) -> approved/cancelled
--          Also support 'blocked_by_icp' status for companies blocked during ICP checks
--          Note: 'approved' replaces 'completed' for clarity (approved = verified and approved)
-- Date: 2025-11-23

-- Step 1: Drop the old CHECK constraint FIRST to allow updating values
-- This must happen before any data changes to avoid constraint violations
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'companies_processing_status_check'
  ) THEN
    ALTER TABLE companies DROP CONSTRAINT companies_processing_status_check;
  END IF;
END $$;

-- Step 2: Update existing 'completed' records to 'approved'
-- Now that the constraint is dropped, we can safely update
UPDATE companies 
SET processing_status = 'approved' 
WHERE processing_status = 'completed';

-- Step 3: Add new CHECK constraint with all statuses included
ALTER TABLE companies 
  ADD CONSTRAINT companies_processing_status_check 
  CHECK (processing_status IN (
    'pending', 
    'scheduled', 
    'processing', 
    'processed', 
    'approved', 
    'cancelled', 
    'failed',
    'blocked_by_icp'
  ));

-- Step 4: Update the generated processing_simple_status column to handle new statuses
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

  -- Recreate with updated logic including all statuses
  -- Note: 'processed' and 'approved' are different stages:
  --       - 'processed' = enrichment/research/scoring complete, waiting for verification task
  --       - 'approved' = verified and approved via verification task
  ALTER TABLE companies 
    ADD COLUMN processing_simple_status TEXT GENERATED ALWAYS AS (
      CASE 
        WHEN processing_status = 'approved' THEN 'approved'
        WHEN processing_status = 'processed' THEN 'processed'
        WHEN processing_status IN ('pending', 'scheduled', 'processing') THEN 'processing'
        WHEN processing_status = 'failed' THEN 'failed'
        WHEN processing_status = 'cancelled' THEN 'cancelled'
        WHEN processing_status = 'blocked_by_icp' THEN 'blocked'
        ELSE NULL
      END
    ) STORED;
END $$;

-- Ensure index exists for filtering by status
CREATE INDEX IF NOT EXISTS idx_companies_processing_simple_status ON companies(processing_simple_status);

-- Update documentation
COMMENT ON COLUMN companies.processing_status IS 'Status of company data processing: pending (not started), scheduled (queued for processing), processing (in progress), processed (enrichment/research/scoring complete, waiting for verification), approved (verified and approved via verification task), cancelled (verified and rejected via verification task), failed (error occurred), blocked_by_icp (blocked by ICP hard filters)';
COMMENT ON COLUMN companies.processing_simple_status IS 'Generated status derived from processing_status: approved (approved - verified and approved), processed (processed - waiting for verification), processing (pending/scheduled/processing), failed, cancelled, blocked';

