-- Migration: Remove conversation_id from tasks table
-- Description: Removes the unused conversation_id column from tasks table
-- Author: System
-- Date: 2025-07-29

-- Remove the conversation_id column from tasks table
ALTER TABLE tasks DROP COLUMN IF EXISTS conversation_id;

-- Remove the index on conversation_id (if it exists)
DROP INDEX IF EXISTS idx_tasks_conversation_id;

-- Add comment explaining the change
COMMENT ON TABLE tasks IS 'Tasks table without conversation_id - simplified for email review workflow'; 