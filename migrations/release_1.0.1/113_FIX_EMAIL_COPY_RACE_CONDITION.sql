-- =====================================================
-- CRITICAL FIX: Empty Email Copy Race Condition
-- =====================================================
-- This migration adds the 'email_generation_processing' 
-- task type to fix a race condition causing empty email tasks
--
-- APPLY THIS IMMEDIATELY to your production database
-- =====================================================

-- Step 1: Add the missing task type and status enum values
-- IMPORTANT: These must be in separate transactions to be committed before use

-- Add email_generation_processing to task_type enum
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_enum e
        JOIN pg_type t ON e.enumtypid = t.oid
        WHERE t.typname = 'task_type' AND e.enumlabel = 'email_generation_processing'
    ) THEN
        ALTER TYPE task_type ADD VALUE 'email_generation_processing';
        RAISE NOTICE 'Successfully added email_generation_processing to task_type enum';
    ELSE
        RAISE NOTICE 'email_generation_processing already exists in task_type enum';
    END IF;
END $$;

-- Add in_progress to task_status enum (MUST be in separate transaction)
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_enum e
        JOIN pg_type t ON e.enumtypid = t.oid
        WHERE t.typname = 'task_status' AND e.enumlabel = 'in_progress'
    ) THEN
        ALTER TYPE task_status ADD VALUE 'in_progress';
        RAISE NOTICE 'Successfully added in_progress to task_status enum';
    ELSE
        RAISE NOTICE 'in_progress already exists in task_status enum';
    END IF;
END $$;

-- Step 2: Verify the enum now has all required values
DO $$
DECLARE
    task_type_values text;
    task_status_values text;
BEGIN
    SELECT string_agg(enumlabel, ', ' ORDER BY enumsortorder) INTO task_type_values
    FROM pg_enum e
    JOIN pg_type t ON e.enumtypid = t.oid
    WHERE t.typname = 'task_type';
    
    SELECT string_agg(enumlabel, ', ' ORDER BY enumsortorder) INTO task_status_values
    FROM pg_enum e
    JOIN pg_type t ON e.enumtypid = t.oid
    WHERE t.typname = 'task_status';
    
    RAISE NOTICE 'Current task_type enum values: %', task_type_values;
    RAISE NOTICE 'Current task_status enum values: %', task_status_values;
END $$;

-- Step 3: Clean up any stuck processing tasks (optional but recommended)
-- This handles any tasks that might be stuck from failed attempts before the fix
-- NOTE: We only clean up 'pending' tasks here since 'in_progress' was just added
-- and may not be usable in the same transaction. Any 'in_progress' tasks will be
-- cleaned up in a subsequent migration or by the application logic.
UPDATE tasks
SET 
    status = 'cancelled', 
    updated_at = now(),
    metadata = CASE 
        WHEN metadata IS NULL THEN 
            jsonb_build_object(
                'cleanup_reason', 
                'Stuck processing task cleaned up during migration 113',
                'cleaned_at', now()
            )
        ELSE 
            metadata || jsonb_build_object(
                'cleanup_reason', 
                'Stuck processing task cleaned up during migration 113',
                'cleaned_at', now()
            )
    END
WHERE task_type = 'email_generation_processing'
  AND status = 'pending'
  AND created_at < now() - interval '10 minutes';

-- Step 4: Report summary
DO $$
DECLARE
    cleanup_count int;
BEGIN
    SELECT count(*) INTO cleanup_count
    FROM tasks
    WHERE metadata->>'cleanup_reason' = 'Stuck processing task cleaned up during migration 113';
    
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Migration 113 completed successfully!';
    RAISE NOTICE 'Cleaned up % stuck processing tasks', cleanup_count;
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Next steps:';
    RAISE NOTICE '1. Verify task_type enum has: review_draft, meeting, email_generation_processing';
    RAISE NOTICE '2. Verify task_status enum has: pending, in_progress, completed, cancelled';
    RAISE NOTICE '3. Monitor webhook logs for successful processing task creation';
    RAISE NOTICE '4. Confirm no more empty email copy tasks are created';
    RAISE NOTICE '========================================';
END $$;

-- Step 5: Add helpful comment
COMMENT ON TYPE task_type IS 
'Valid task types for the tasks table:
- review_draft: Email drafts awaiting review/approval before sending
- meeting: Meeting scheduling and coordination tasks
- email_generation_processing: Lock task to prevent duplicate email generation during webhook processing';

-- =====================================================
-- VERIFICATION QUERIES
-- =====================================================

-- Check all enum values
SELECT 'Current task_type values:' as info;
SELECT enumlabel as task_type, enumsortorder as sort_order
FROM pg_enum e
JOIN pg_type t ON e.enumtypid = t.oid
WHERE t.typname = 'task_type'
ORDER BY enumsortorder;

SELECT 'Current task_status values:' as info;
SELECT enumlabel as task_status, enumsortorder as sort_order
FROM pg_enum e
JOIN pg_type t ON e.enumtypid = t.oid
WHERE t.typname = 'task_status'
ORDER BY enumsortorder;

-- Check for any remaining stuck processing tasks
-- NOTE: Only checking 'pending' since 'in_progress' was just added
SELECT 'Remaining stuck processing tasks (pending only):' as info;
SELECT count(*) as stuck_count
FROM tasks
WHERE task_type = 'email_generation_processing'
  AND status = 'pending'
  AND created_at < now() - interval '5 minutes';

-- Check recent tasks created
SELECT 'Recent tasks (last hour):' as info;
SELECT task_type, status, count(*) as count
FROM tasks
WHERE created_at > now() - interval '1 hour'
GROUP BY task_type, status
ORDER BY task_type, status;


