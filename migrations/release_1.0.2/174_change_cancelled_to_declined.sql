-- Migration: Change 'cancelled' to 'declined' for company processing_status
-- Purpose: Use more accurate terminology - companies are "declined" not "cancelled"
-- Date: 2025-11-23
-- 
-- This migration:
-- 1. Updates existing 'cancelled' records to 'declined'
-- 2. Updates the CHECK constraint to use 'declined' instead of 'cancelled'
-- 3. Updates database functions that reference 'cancelled'

-- Step 1: First, drop the constraint temporarily to allow updates
-- This ensures we can update records even if constraint is blocking
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'companies_processing_status_check'
  ) THEN
    ALTER TABLE companies DROP CONSTRAINT companies_processing_status_check;
    RAISE NOTICE 'Dropped existing companies_processing_status_check constraint';
  END IF;
END $$;

-- Step 2: Update existing 'cancelled' records to 'declined'
-- Now safe to do since constraint is dropped
UPDATE companies 
SET processing_status = 'declined' 
WHERE processing_status = 'cancelled';

-- Step 3: Add new constraint with 'declined' instead of 'cancelled'
DO $$
DECLARE
  invalid_count integer;
BEGIN
  -- First, fix any invalid statuses that might exist
  -- Update any 'cancelled' that might have been missed
  UPDATE companies 
  SET processing_status = 'declined' 
  WHERE processing_status = 'cancelled';
  
  GET DIAGNOSTICS invalid_count = ROW_COUNT;
  IF invalid_count > 0 THEN
    RAISE NOTICE 'Updated % additional rows from ''cancelled'' to ''declined''', invalid_count;
  END IF;
  
  -- Now add the constraint with 'declined' instead of 'cancelled'
  ALTER TABLE companies 
    ADD CONSTRAINT companies_processing_status_check 
    CHECK (processing_status IN (
      'pending', 
      'scheduled', 
      'processing', 
      'processed', 
      'approved', 
      'declined', 
      'failed',
      'blocked_by_icp'
    ));
  RAISE NOTICE 'Added companies_processing_status_check constraint with declined instead of cancelled';
END $$;

-- Step 3: Update get_dashboard_stats function to use 'declined'
DROP FUNCTION IF EXISTS get_dashboard_stats(text);

CREATE OR REPLACE FUNCTION get_dashboard_stats(p_organization_id text)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  result jsonb;
BEGIN
  SELECT jsonb_build_object(
    'tasks', (
      SELECT jsonb_build_object(
        'totalTasks', count(*),
        'pendingTasks', count(*) FILTER (WHERE status = 'pending'),
        'inProgressTasks', count(*) FILTER (WHERE status = 'in_progress'),
        'completedTasks', count(*) FILTER (WHERE status = 'completed'),
        'cancelledTasks', count(*) FILTER (WHERE status = 'cancelled'),
        'scheduledTasks', 0,
        'reviewDraftTasks', count(*) FILTER (WHERE task_type::text = 'review_draft'),
        'companyVerificationTasks', count(*) FILTER (WHERE task_type::text = 'company_verification'),
        'overdueTasks', count(*) FILTER (WHERE status IN ('pending', 'in_progress') AND due_date < now()),
        'dueTodayTasks', count(*) FILTER (WHERE status IN ('pending', 'in_progress') AND due_date >= date_trunc('day', now()) AND due_date < date_trunc('day', now()) + interval '1 day'),
        'dueThisWeekTasks', count(*) FILTER (WHERE status IN ('pending', 'in_progress') AND due_date >= date_trunc('week', now()) AND due_date < date_trunc('week', now()) + interval '1 week')
      )
      FROM tasks
      WHERE organization_id = p_organization_id
    ),
    'companies', jsonb_build_object(
      'total', count(*),
      'all_companies', count(*),
      'scheduled', count(*) FILTER (WHERE processing_status = 'scheduled'),
      'processing', count(*) FILTER (WHERE processing_status IN ('processing', 'pending')),
      'processed', count(*) FILTER (WHERE processing_status = 'processed'),
      'approved', count(*) FILTER (WHERE processing_status = 'approved'),
      'declined', count(*) FILTER (WHERE processing_status = 'declined'),
      'blocked_by_icp', count(*) FILTER (WHERE blocked_by_icp = true),
      'failed', count(*) FILTER (WHERE processing_status = 'failed')
    ),
    'contacts', jsonb_build_object(
      'total', (SELECT count(*) FROM contacts WHERE organization_id = p_organization_id),
      'total_contacts', (SELECT count(*) FROM contacts WHERE organization_id = p_organization_id),
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
COMMENT ON COLUMN companies.processing_status IS 'Status of company data processing. Flow: scheduled → processing → processed → (approved OR declined OR blocked_by_icp). Valid values: pending, scheduled, processing, processed, approved, declined, failed, blocked_by_icp';

