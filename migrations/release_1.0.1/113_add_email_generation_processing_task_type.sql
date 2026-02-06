-- Description: Add email_generation_processing task type to prevent duplicate email generation
-- Date: 2025-10-27
-- This task type is used as a lock to prevent multiple webhook deliveries from 
-- generating emails for the same contact simultaneously

-- Add new task type to the enum
-- Note: In PostgreSQL, new enum values must be committed before they can be used
-- So we check if it exists first to make this migration idempotent
DO $$ 
BEGIN
    -- Check if the value already exists
    IF NOT EXISTS (
        SELECT 1 FROM pg_enum e
        JOIN pg_type t ON e.enumtypid = t.oid
        WHERE t.typname = 'task_type' AND e.enumlabel = 'email_generation_processing'
    ) THEN
        -- Add the new enum value
        ALTER TYPE task_type ADD VALUE 'email_generation_processing';
        RAISE NOTICE 'Added email_generation_processing to task_type enum';
    ELSE
        RAISE NOTICE 'email_generation_processing already exists in task_type enum';
    END IF;
END $$;

-- Add comment explaining the purpose
COMMENT ON TYPE task_type IS 'Valid task types: review_draft (email drafts to review), meeting (meeting scheduling), email_generation_processing (lock during email generation)';
