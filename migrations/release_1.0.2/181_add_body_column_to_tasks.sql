-- =====================================================
-- Add body column to tasks table
-- =====================================================
-- Purpose:
-- - pre_generated_copy: Original AI-generated email body (reference, never changes)
-- - body: User-editable email body (what gets sent to Gmail API)
--
-- This allows us to always have the original AI copy for reference
-- while users can freely edit the body before sending.
-- =====================================================

-- =============================================================================
-- PART 1: Add body column if it doesn't exist
-- =============================================================================

ALTER TABLE public.tasks 
ADD COLUMN IF NOT EXISTS body text NULL;

-- Log column addition
DO $$
BEGIN
    RAISE NOTICE '✅ Added body column to tasks table';
END $$;

-- =============================================================================
-- PART 2: Copy pre_generated_copy to body where body is empty
-- =============================================================================

-- Only copy if body is null/empty and pre_generated_copy has content
UPDATE public.tasks
SET body = pre_generated_copy,
    updated_at = NOW()
WHERE (body IS NULL OR body = '')
  AND pre_generated_copy IS NOT NULL
  AND pre_generated_copy != '';

-- Log migration count
DO $$
DECLARE
    updated_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO updated_count
    FROM public.tasks
    WHERE body IS NOT NULL AND body != '';
    
    RAISE NOTICE '✅ Copied pre_generated_copy to body for % tasks', updated_count;
END $$;

-- =============================================================================
-- PART 3: Add comment documenting field usage
-- =============================================================================

COMMENT ON COLUMN public.tasks.body IS 'User-editable email body. This is what gets sent to Gmail API. Initially copied from pre_generated_copy.';
COMMENT ON COLUMN public.tasks.pre_generated_copy IS 'Original AI-generated email body. Kept as reference, never modified after initial generation.';

-- =============================================================================
-- PART 4: Fill empty created_by_user_id with 'api' for server-created tasks
-- =============================================================================

-- Update existing tasks that have no created_by_user_id to 'api'
-- These were created by the server/API but the field wasn't set
UPDATE public.tasks
SET created_by_user_id = 'api',
    updated_at = NOW()
WHERE created_by_user_id IS NULL
  AND task_type = 'review_draft';

-- Log migration count
DO $$
DECLARE
    updated_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO updated_count
    FROM public.tasks
    WHERE created_by_user_id = 'api';
    
    RAISE NOTICE '✅ Set created_by_user_id to api for % review_draft tasks', updated_count;
END $$;

-- =============================================================================
-- PART 5: Summary
-- =============================================================================

DO $$
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Body column added to tasks table!';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Field usage:';
    RAISE NOTICE '  - pre_generated_copy: Original AI copy (reference)';
    RAISE NOTICE '  - body: User-editable copy (sent to Gmail)';
    RAISE NOTICE '  - created_by_user_id: api (for server-created tasks)';
    RAISE NOTICE '========================================';
END $$;

