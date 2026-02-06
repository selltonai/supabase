-- Migration: Fix company_verification task type enum
-- Date: 2025-11-03
-- Description: Ensures company_verification exists in task_type enum
-- This is a critical fix for task creation functionality
-- Note: ALTER TYPE ADD VALUE cannot be run inside a function, so we use a DO block

DO $$ 
BEGIN
    -- Check if the value already exists
    IF NOT EXISTS (
        SELECT 1 
        FROM pg_enum e
        JOIN pg_type t ON e.enumtypid = t.oid
        WHERE t.typname = 'task_type' 
        AND e.enumlabel = 'company_verification'
    ) THEN
        -- Add the new enum value
        -- Note: This operation commits immediately and cannot be rolled back
        ALTER TYPE task_type ADD VALUE 'company_verification';
        RAISE NOTICE 'Added company_verification to task_type enum';
    ELSE
        RAISE NOTICE 'company_verification already exists in task_type enum - skipping';
    END IF;
EXCEPTION
    WHEN duplicate_object THEN
        RAISE NOTICE 'company_verification already exists in task_type enum (exception caught)';
    WHEN OTHERS THEN
        RAISE WARNING 'Error adding company_verification to task_type enum: %', SQLERRM;
END $$;

-- Update comment to include company_verification
COMMENT ON TYPE task_type IS 'Valid task types: review_draft (email drafts to review), meeting (meeting scheduling), company_verification (company verification workflows), email_generation_processing (lock during email generation)';

