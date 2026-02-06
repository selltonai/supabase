-- Migration: Ensure processing_status constraint includes 'approved' and all valid statuses
-- Purpose: Fix constraint violation when updating companies to 'approved' status
-- Date: 2025-11-23
-- 
-- Issue: The CHECK constraint companies_processing_status_check was rejecting 'approved' status
-- This migration ensures the constraint includes all valid statuses

-- Step 1: First, fix any invalid statuses in existing rows
-- Map any invalid or legacy statuses to valid ones
DO $$
DECLARE
  invalid_count integer;
BEGIN
  -- Update 'completed' to 'processed' first (safer - constraint likely allows 'processed')
  -- Then after constraint is updated, we can update 'processed' -> 'approved' if needed
  UPDATE companies 
  SET processing_status = 'processed' 
  WHERE processing_status = 'completed';
  
  GET DIAGNOSTICS invalid_count = ROW_COUNT;
  IF invalid_count > 0 THEN
    RAISE NOTICE 'Updated % rows from ''completed'' to ''processed''', invalid_count;
  END IF;
  
  -- Update NULL to 'pending' (default status)
  UPDATE companies 
  SET processing_status = 'pending' 
  WHERE processing_status IS NULL;
  
  GET DIAGNOSTICS invalid_count = ROW_COUNT;
  IF invalid_count > 0 THEN
    RAISE NOTICE 'Updated % rows from NULL to ''pending''', invalid_count;
  END IF;
  
  -- Update any other invalid statuses to 'pending' as fallback
  -- BUT: Only update statuses that are NOT in the valid list
  -- This prevents trying to update 'approved' if constraint doesn't allow it yet
  UPDATE companies 
  SET processing_status = 'pending' 
  WHERE processing_status NOT IN (
    'pending', 
    'scheduled', 
    'processing', 
    'processed', 
    'approved', 
    'cancelled', 
    'failed',
    'blocked_by_icp'
  );
  
  GET DIAGNOSTICS invalid_count = ROW_COUNT;
  IF invalid_count > 0 THEN
    RAISE NOTICE 'Updated % rows with invalid statuses to ''pending''', invalid_count;
  END IF;
END $$;

-- Step 2: Drop the existing constraint if it exists
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'companies_processing_status_check'
  ) THEN
    ALTER TABLE companies DROP CONSTRAINT companies_processing_status_check;
    RAISE NOTICE 'Dropped existing companies_processing_status_check constraint';
  ELSE
    RAISE NOTICE 'companies_processing_status_check constraint does not exist';
  END IF;
END $$;

-- Step 3: Add the constraint with ALL valid statuses including 'approved'
DO $$
BEGIN
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
  RAISE NOTICE 'Added companies_processing_status_check constraint with all valid statuses including approved';
END $$;

-- Step 4: Verify the constraint was created correctly
DO $$
DECLARE
  constraint_def text;
BEGIN
  SELECT pg_get_constraintdef(oid) INTO constraint_def
  FROM pg_constraint 
  WHERE conname = 'companies_processing_status_check';
  
  IF constraint_def IS NULL THEN
    RAISE EXCEPTION 'Constraint companies_processing_status_check was not created';
  ELSE
    RAISE NOTICE 'Constraint definition: %', constraint_def;
  END IF;
END $$;

-- Update documentation
COMMENT ON COLUMN companies.processing_status IS 'Status of company data processing. Flow: scheduled → processing → processed → (approved OR cancelled OR blocked_by_icp). Valid values: pending, scheduled, processing, processed, approved, cancelled, failed, blocked_by_icp';
