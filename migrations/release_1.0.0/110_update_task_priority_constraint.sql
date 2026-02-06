-- Migration: Update Task Priority Constraint
-- Description: Updates the task priority constraint to include 'urgent' and match the TaskPriority enum
-- Author: System
-- Date: 2025-01-30

-- Drop the existing priority constraint
ALTER TABLE tasks DROP CONSTRAINT IF EXISTS tasks_priority_check;

-- Add the updated priority constraint to match TaskPriority enum
ALTER TABLE tasks ADD CONSTRAINT tasks_priority_check 
  CHECK (priority IN ('low', 'normal', 'high', 'urgent'));

-- Add comment explaining the constraint
COMMENT ON COLUMN tasks.priority IS 'Task priority level: low, normal, high, urgent (matches TaskPriority enum)'; 