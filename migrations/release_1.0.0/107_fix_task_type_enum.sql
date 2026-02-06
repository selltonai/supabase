-- Migration: Fix Task Type Enum
-- Description: Drop and recreate task_type enum to only include review_draft and meeting
-- Author: System
-- Date: 2025-01-29

-- First, update any existing tasks with invalid task types to review_draft
UPDATE tasks 
SET task_type = 'review_draft'
WHERE task_type NOT IN ('review_draft', 'meeting');

-- Add a temporary text column
ALTER TABLE tasks ADD COLUMN task_type_temp TEXT;

-- Copy the data to the temporary column
UPDATE tasks SET task_type_temp = task_type::text;

-- Drop the old column and enum
ALTER TABLE tasks DROP COLUMN task_type;
DROP TYPE IF EXISTS task_type CASCADE;

-- Create new enum with only the valid types
CREATE TYPE task_type AS ENUM ('review_draft', 'meeting');

-- Add the new column with the new enum type
ALTER TABLE tasks ADD COLUMN task_type task_type;

-- Update the new column with the data from the temporary column
UPDATE tasks SET task_type = 
  CASE 
    WHEN task_type_temp IN ('review_draft', 'meeting') THEN task_type_temp::task_type
    ELSE 'review_draft'::task_type
  END;

-- Drop the temporary column
ALTER TABLE tasks DROP COLUMN task_type_temp;

-- Add comment
COMMENT ON TYPE task_type IS 'Task types: review_draft for email reviews, meeting for meeting preparation'; 