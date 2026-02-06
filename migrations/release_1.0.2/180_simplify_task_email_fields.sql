-- =====================================================
-- Simplify Task Email Fields
-- =====================================================
-- Changes:
-- 1. Remove final_copy column (use pre_generated_copy as reference)
-- 2. Ensure subject field is used for actual email subject
-- 3. title remains as display title (e.g., "Review email draft for X")
--
-- Field usage after this migration:
-- - title: Display title (e.g., "Review email draft for John Doe")
-- - subject: Actual email subject line to be sent (editable in frontend)
-- - pre_generated_copy: Original AI-generated email body (reference)
-- - body: User-editable email body (sent to Gmail API) - added in migration 181
-- - metadata.subject: DEPRECATED - use subject column instead
-- =====================================================

-- =============================================================================
-- PART 1: Migrate final_copy to pre_generated_copy where different (if column exists)
-- =============================================================================

-- If a task has final_copy that's different from pre_generated_copy,
-- update pre_generated_copy to final_copy (since that's the edited version)
-- Only run if final_copy column exists
DO $$
DECLARE
    column_exists BOOLEAN;
    updated_count INTEGER := 0;
BEGIN
    SELECT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_schema = 'public' 
        AND table_name = 'tasks' 
        AND column_name = 'final_copy'
    ) INTO column_exists;
    
    IF column_exists THEN
        UPDATE public.tasks
        SET pre_generated_copy = final_copy,
            updated_at = NOW()
        WHERE final_copy IS NOT NULL 
          AND final_copy != '' 
          AND (pre_generated_copy IS NULL OR final_copy != pre_generated_copy);
        
        GET DIAGNOSTICS updated_count = ROW_COUNT;
        RAISE NOTICE '✅ Migrated % tasks with edited final_copy to pre_generated_copy', updated_count;
    ELSE
        RAISE NOTICE '⏭️ final_copy column does not exist - skipping migration';
    END IF;
END $$;

-- =============================================================================
-- PART 2: Migrate metadata.subject to subject column
-- =============================================================================

-- Copy subject from metadata to subject column where subject column is empty
UPDATE public.tasks
SET subject = metadata->>'subject',
    updated_at = NOW()
WHERE (subject IS NULL OR subject = '')
  AND metadata->>'subject' IS NOT NULL
  AND metadata->>'subject' != '';

-- Log migration
DO $$
DECLARE
    updated_count INTEGER;
BEGIN
    GET DIAGNOSTICS updated_count = ROW_COUNT;
    RAISE NOTICE '✅ Migrated % tasks with metadata.subject to subject column', updated_count;
END $$;

-- =============================================================================
-- PART 3: Drop deprecated final_copy column
-- =============================================================================

-- Drop final_copy column (pre_generated_copy is used for email body)
ALTER TABLE public.tasks DROP COLUMN IF EXISTS final_copy;

-- Log completion
DO $$
BEGIN
    RAISE NOTICE '✅ Dropped final_copy column from tasks table';
END $$;

-- =============================================================================
-- PART 4: Add comments documenting field usage
-- =============================================================================

COMMENT ON COLUMN public.tasks.title IS 'Display title for the task (e.g., "Review email draft for John Doe")';
COMMENT ON COLUMN public.tasks.subject IS 'Actual email subject line to be sent. Used for email-related tasks.';
COMMENT ON COLUMN public.tasks.pre_generated_copy IS 'Email body content. Contains original AI-generated text, or user-edited text if modified.';

-- =============================================================================
-- PART 5: Summary
-- =============================================================================

DO $$
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Task email field simplification complete!';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Field usage:';
    RAISE NOTICE '  - title: Display title for UI';
    RAISE NOTICE '  - subject: Email subject line (editable)';
    RAISE NOTICE '  - pre_generated_copy: Email body (editable)';
    RAISE NOTICE '  - metadata: Other context data';
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Removed columns:';
    RAISE NOTICE '  - final_copy (merged into pre_generated_copy)';
    RAISE NOTICE '========================================';
END $$;

