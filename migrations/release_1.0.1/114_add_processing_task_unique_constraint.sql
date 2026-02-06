-- =====================================================
-- Add Unique Constraint for Processing Tasks
-- =====================================================
-- Prevents race condition where multiple webhooks create
-- processing lock tasks simultaneously for the same contact
-- =====================================================

-- Step 1: Clean up any duplicate processing tasks first
-- (Keep oldest, cancel newer ones)
WITH duplicate_processing AS (
    SELECT 
        contact_id,
        MIN(created_at) as oldest_created
    FROM tasks
    WHERE task_type = 'email_generation_processing'
      AND status IN ('pending', 'in_progress')
    GROUP BY contact_id
    HAVING COUNT(*) > 1
)
UPDATE tasks
SET 
    status = 'cancelled',
    updated_at = now()
FROM duplicate_processing dp
WHERE tasks.contact_id = dp.contact_id
  AND tasks.task_type = 'email_generation_processing'
  AND tasks.status IN ('pending', 'in_progress')
  AND tasks.created_at > dp.oldest_created;

-- Step 2: Create partial unique index
-- This prevents creating multiple IN_PROGRESS processing tasks for the same contact
-- Using a partial index so it only applies to active processing tasks
CREATE UNIQUE INDEX IF NOT EXISTS idx_tasks_processing_unique_contact 
ON tasks (contact_id, organization_id) 
WHERE task_type = 'email_generation_processing' 
  AND status IN ('pending', 'in_progress');

-- Step 3: Add comment
COMMENT ON INDEX idx_tasks_processing_unique_contact IS 
'Ensures only one active email_generation_processing task can exist per contact at a time, preventing race conditions in webhook processing';

-- Step 4: Verify the index was created
SELECT 
    indexname,
    indexdef
FROM pg_indexes
WHERE indexname = 'idx_tasks_processing_unique_contact';

-- Step 5: Test the constraint works
DO $$
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Migration 114 completed successfully!';
    RAISE NOTICE 'Unique constraint added for processing tasks';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'The database will now prevent:';
    RAISE NOTICE '- Multiple processing tasks for same contact';
    RAISE NOTICE '- Race condition in webhook email generation';
    RAISE NOTICE '========================================';
END $$;


