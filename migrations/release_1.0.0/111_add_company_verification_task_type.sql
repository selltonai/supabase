-- Description: Add company_verification task type to the task_type enum
-- This migration adds the new task type needed for company verification workflows

-- Step 1: Add the new value to the enum
-- This must be done in its own transaction
ALTER TYPE task_type ADD VALUE IF NOT EXISTS 'company_verification';