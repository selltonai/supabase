-- Migration: Cleanup tasks user fields
-- Description: Remove user_id field and update created_by_user_id defaults
-- Author: System
-- Date: 2025-07-29

-- Remove the user_id column from tasks table (not needed)
ALTER TABLE tasks DROP COLUMN IF EXISTS user_id;

-- Update existing records to use "api" instead of "dev-test-user"
UPDATE tasks 
SET created_by_user_id = 'api' 
WHERE created_by_user_id = 'dev-test-user';

-- Update existing records to use "api" instead of "dev-test-user" for completed_by_user_id
UPDATE tasks 
SET completed_by_user_id = 'api' 
WHERE completed_by_user_id = 'dev-test-user';

-- Add comment explaining the cleanup
COMMENT ON TABLE tasks IS 'Tasks table with cleaned up user fields - user_id removed, created_by_user_id and completed_by_user_id use "api" for system operations'; 