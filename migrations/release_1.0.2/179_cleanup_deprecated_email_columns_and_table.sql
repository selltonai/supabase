-- =====================================================
-- Cleanup Deprecated Email Columns and Table
-- =====================================================
-- Removes send_status and send_error_message columns from tasks table
-- (we use sent_at + status=completed to track sent emails instead)
-- Drops the deprecated email_copy_tasks table
-- =====================================================

-- =============================================================================
-- PART 1: Remove send_status related objects from tasks table
-- =============================================================================

-- Drop the index on send_status
DROP INDEX IF EXISTS idx_tasks_send_status;

-- Drop the check constraint on send_status
ALTER TABLE public.tasks DROP CONSTRAINT IF EXISTS tasks_send_status_check;

-- Drop the send_status column
ALTER TABLE public.tasks DROP COLUMN IF EXISTS send_status;

-- Drop the send_error_message column
ALTER TABLE public.tasks DROP COLUMN IF EXISTS send_error_message;

-- Log what was done
DO $$
BEGIN
    RAISE NOTICE '✅ Dropped send_status and send_error_message columns from tasks table';
END $$;

-- =============================================================================
-- PART 2: Drop the deprecated email_copy_tasks table
-- =============================================================================

-- First check if there's any data that wasn't migrated
DO $$
DECLARE
    email_copy_count INTEGER;
    tasks_review_draft_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO email_copy_count FROM public.email_copy_tasks;
    SELECT COUNT(*) INTO tasks_review_draft_count FROM public.tasks WHERE task_type = 'review_draft';
    
    RAISE NOTICE 'email_copy_tasks table has % records', email_copy_count;
    RAISE NOTICE 'tasks table has % review_draft records', tasks_review_draft_count;
    
    IF email_copy_count > 0 THEN
        RAISE NOTICE '⚠️ email_copy_tasks still has data - verify migration before proceeding';
    END IF;
END $$;

-- Drop indexes on email_copy_tasks
DROP INDEX IF EXISTS idx_email_copy_tasks_contact_id;
DROP INDEX IF EXISTS idx_email_copy_tasks_company_id;
DROP INDEX IF EXISTS idx_email_copy_tasks_campaign_id;
DROP INDEX IF EXISTS idx_email_copy_tasks_organization_id;
DROP INDEX IF EXISTS idx_email_copy_tasks_status;
DROP INDEX IF EXISTS idx_email_copy_tasks_send_status;
DROP INDEX IF EXISTS idx_email_copy_tasks_thread_id;

-- Drop the email_copy_tasks table
DROP TABLE IF EXISTS public.email_copy_tasks;

-- Log completion
DO $$
BEGIN
    RAISE NOTICE '✅ Dropped email_copy_tasks table';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Cleanup complete!';
    RAISE NOTICE '- Removed send_status column from tasks';
    RAISE NOTICE '- Removed send_error_message column from tasks';  
    RAISE NOTICE '- Dropped email_copy_tasks table';
    RAISE NOTICE '========================================';
END $$;

