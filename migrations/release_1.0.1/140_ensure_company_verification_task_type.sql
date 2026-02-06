-- Description: Ensure company_verification task type exists in the task_type enum
-- Date: 2025-01-30
-- This task type is used for company verification workflows
-- Using DO block to check if value exists first to make this migration idempotent

DO $$ 
BEGIN
    -- Check if the value already exists
    IF NOT EXISTS (
        SELECT 1 FROM pg_enum e
        JOIN pg_type t ON e.enumtypid = t.oid
        WHERE t.typname = 'task_type' AND e.enumlabel = 'company_verification'
    ) THEN
        -- Add the new enum value
        ALTER TYPE task_type ADD VALUE 'company_verification';
        RAISE NOTICE 'Added company_verification to task_type enum';
    ELSE
        RAISE NOTICE 'company_verification already exists in task_type enum';
    END IF;
END $$;

-- Update comment to include company_verification
COMMENT ON TYPE task_type IS 'Valid task types: review_draft (email drafts to review), meeting (meeting scheduling), company_verification (company verification workflows), email_generation_processing (lock during email generation)';














