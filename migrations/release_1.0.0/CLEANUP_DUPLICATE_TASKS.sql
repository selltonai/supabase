-- =====================================================
-- Clean Up Duplicate Email Copy Tasks
-- =====================================================
-- This script finds and removes duplicate pending tasks
-- for the same contact, keeping only the oldest one
-- (which likely has the better/first email copy)
-- =====================================================

-- Step 1: Find all contacts with duplicate pending review_draft tasks
WITH duplicate_tasks AS (
    SELECT 
        contact_id,
        COUNT(*) as task_count,
        ARRAY_AGG(id ORDER BY created_at) as task_ids,
        ARRAY_AGG(created_at ORDER BY created_at) as created_dates,
        MIN(created_at) as oldest_task_created
    FROM tasks
    WHERE task_type = 'review_draft'
      AND status = 'pending'
    GROUP BY contact_id
    HAVING COUNT(*) > 1
),

-- Step 2: Identify which tasks to keep (oldest) and which to remove (newer)
tasks_to_cancel AS (
    SELECT 
        t.id,
        t.contact_id,
        t.created_at,
        t.title,
        dt.task_count,
        dt.oldest_task_created,
        CASE 
            WHEN t.created_at = dt.oldest_task_created THEN 'KEEP'
            ELSE 'CANCEL'
        END as action
    FROM tasks t
    INNER JOIN duplicate_tasks dt ON t.contact_id = dt.contact_id
    WHERE t.task_type = 'review_draft'
      AND t.status = 'pending'
)

-- Step 3: Show what will be cleaned up (for review)
SELECT 
    'PREVIEW: Duplicate tasks found' as info,
    contact_id,
    task_count as total_tasks,
    COUNT(*) FILTER (WHERE action = 'CANCEL') as will_cancel,
    COUNT(*) FILTER (WHERE action = 'KEEP') as will_keep
FROM tasks_to_cancel
GROUP BY contact_id, task_count
ORDER BY task_count DESC;

-- Step 4: Detailed list of tasks to be cancelled
SELECT 
    '-- Tasks that will be CANCELLED:' as info,
    ttc.id as task_id,
    ttc.contact_id,
    c.name as contact_name,
    c.email as contact_email,
    ttc.created_at,
    ttc.title,
    (ttc.created_at - ttc.oldest_task_created) as time_after_first_task
FROM tasks_to_cancel ttc
LEFT JOIN contacts c ON ttc.contact_id = c.id
WHERE ttc.action = 'CANCEL'
ORDER BY ttc.contact_id, ttc.created_at;

-- =====================================================
-- APPLY THE CLEANUP (Uncomment to execute)
-- =====================================================

-- Uncomment the following block to actually cancel the duplicate tasks:

/*
WITH duplicate_tasks AS (
    SELECT 
        contact_id,
        COUNT(*) as task_count,
        MIN(created_at) as oldest_task_created
    FROM tasks
    WHERE task_type = 'review_draft'
      AND status = 'pending'
    GROUP BY contact_id
    HAVING COUNT(*) > 1
)
UPDATE tasks
SET 
    status = 'cancelled',
    updated_at = now(),
    metadata = CASE 
        WHEN metadata IS NULL THEN 
            jsonb_build_object(
                'cancellation_reason', 'Duplicate task - keeping oldest task only',
                'cancelled_by', 'cleanup_script',
                'cancelled_at', now()
            )
        ELSE 
            metadata || jsonb_build_object(
                'cancellation_reason', 'Duplicate task - keeping oldest task only',
                'cancelled_by', 'cleanup_script',
                'cancelled_at', now()
            )
    END
FROM duplicate_tasks dt
WHERE tasks.contact_id = dt.contact_id
  AND tasks.task_type = 'review_draft'
  AND tasks.status = 'pending'
  AND tasks.created_at > dt.oldest_task_created;

-- Report results
SELECT 
    'Cleanup completed!' as info,
    COUNT(*) as tasks_cancelled
FROM tasks
WHERE metadata->>'cancelled_by' = 'cleanup_script';
*/

-- =====================================================
-- VERIFICATION QUERIES (Run after cleanup)
-- =====================================================

-- Check for remaining duplicates
SELECT 
    'Remaining duplicates after cleanup:' as info;

SELECT 
    contact_id,
    COUNT(*) as task_count,
    ARRAY_AGG(id ORDER BY created_at) as task_ids,
    ARRAY_AGG(created_at ORDER BY created_at) as created_dates
FROM tasks
WHERE task_type = 'review_draft'
  AND status = 'pending'
GROUP BY contact_id
HAVING COUNT(*) > 1;

-- Check recent task creation patterns
SELECT 
    'Recent tasks (last hour):' as info;

SELECT 
    DATE_TRUNC('minute', created_at) as minute,
    task_type,
    status,
    COUNT(*) as count
FROM tasks
WHERE created_at > now() - interval '1 hour'
GROUP BY DATE_TRUNC('minute', created_at), task_type, status
ORDER BY minute DESC;

