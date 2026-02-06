-- =====================================================
-- Add Unique Constraint for Pending Review Draft Tasks
-- =====================================================
-- Prevents race condition where multiple webhook calls or
-- contact extraction processes create duplicate first email
-- tasks for the same contact
-- =====================================================

-- Step 1: First, show what duplicates exist (for debugging)
DO $$
DECLARE
    dup_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO dup_count
    FROM (
        SELECT contact_id, organization_id, COUNT(*) as cnt
        FROM tasks
        WHERE task_type = 'review_draft'
          AND status = 'pending'
          AND thread_id IS NULL
        GROUP BY contact_id, organization_id
        HAVING COUNT(*) > 1
    ) dups;
    
    RAISE NOTICE 'Found % contact(s) with duplicate pending first-email tasks', dup_count;
END $$;

-- Step 2: Clean up duplicates using row_number to keep only ONE task per contact
-- This handles cases where duplicates have the same created_at timestamp
-- We keep the task with the lowest ID (first inserted)
WITH ranked_tasks AS (
    SELECT 
        id,
        contact_id,
        organization_id,
        ROW_NUMBER() OVER (
            PARTITION BY contact_id, organization_id 
            ORDER BY created_at ASC, id ASC  -- Keep oldest, tie-break by ID
        ) as rn
    FROM tasks
    WHERE task_type = 'review_draft'
      AND status = 'pending'
      AND thread_id IS NULL
),
tasks_to_cancel AS (
    SELECT id 
    FROM ranked_tasks 
    WHERE rn > 1  -- All except the first one
)
UPDATE tasks
SET 
    status = 'cancelled',
    updated_at = now(),
    metadata = CASE 
        WHEN metadata IS NULL OR metadata = 'null'::jsonb THEN 
            '{"cancelled_reason": "duplicate_first_email_cleanup_v2"}'::jsonb
        WHEN jsonb_typeof(metadata) = 'object' THEN 
            metadata || '{"cancelled_reason": "duplicate_first_email_cleanup_v2"}'::jsonb
        ELSE 
            '{"cancelled_reason": "duplicate_first_email_cleanup_v2"}'::jsonb
    END
WHERE id IN (SELECT id FROM tasks_to_cancel);

-- Step 3: Verify cleanup worked
DO $$
DECLARE
    remaining_dups INTEGER;
BEGIN
    SELECT COUNT(*) INTO remaining_dups
    FROM (
        SELECT contact_id, organization_id, COUNT(*) as cnt
        FROM tasks
        WHERE task_type = 'review_draft'
          AND status = 'pending'
          AND thread_id IS NULL
        GROUP BY contact_id, organization_id
        HAVING COUNT(*) > 1
    ) dups;
    
    IF remaining_dups > 0 THEN
        RAISE EXCEPTION 'Cleanup failed! Still have % contacts with duplicate tasks', remaining_dups;
    ELSE
        RAISE NOTICE 'Cleanup successful - no remaining duplicates';
    END IF;
END $$;

-- Step 4: Create partial unique index
-- This prevents creating multiple pending review_draft tasks (first emails only) for the same contact
-- Using a partial index so it only applies to:
-- - pending review_draft tasks
-- - tasks WITHOUT a thread_id (first emails only, not replies)
CREATE UNIQUE INDEX IF NOT EXISTS idx_tasks_review_draft_unique_first_email 
ON tasks (contact_id, organization_id) 
WHERE task_type = 'review_draft' 
  AND status = 'pending'
  AND thread_id IS NULL;

-- Step 5: Add comment
COMMENT ON INDEX idx_tasks_review_draft_unique_first_email IS 
'Ensures only one pending first-email review_draft task can exist per contact at a time. Does not apply to replies (tasks with thread_id) to allow multiple reply drafts. Prevents race conditions in webhook and contact extraction processing.';

-- Step 6: Verify the index was created
SELECT 
    indexname,
    indexdef
FROM pg_indexes
WHERE indexname = 'idx_tasks_review_draft_unique_first_email';

-- Step 7: Notify completion
DO $$
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Unique constraint added for first-email review_draft tasks';
    RAISE NOTICE 'This prevents duplicate first emails for the same contact';
    RAISE NOTICE 'Reply drafts (with thread_id) are NOT affected';
    RAISE NOTICE '========================================';
END $$;

