-- Migration: Allow NULL Task Priority
-- Description: Allows NULL values for task priority since it will be calculated dynamically when fetched
-- Author: System
-- Date: 2025-01-30

-- Drop the existing priority constraint
ALTER TABLE tasks DROP CONSTRAINT IF EXISTS tasks_priority_check;

-- Remove the default value for priority
ALTER TABLE tasks ALTER COLUMN priority DROP DEFAULT;

-- Add the updated priority constraint to allow NULL values
ALTER TABLE tasks ADD CONSTRAINT tasks_priority_check 
  CHECK (priority IS NULL OR priority IN ('low', 'normal', 'high', 'urgent'));

-- Add comment explaining the constraint
COMMENT ON COLUMN tasks.priority IS 'Task priority level: calculated dynamically when fetched, or saved when task is completed/cancelled. Values: low, normal, high, urgent, or NULL for pending tasks.'; 