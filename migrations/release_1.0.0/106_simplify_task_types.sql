-- Migration: Simplify Task Types
-- Description: Remove unused task types, keep only review_draft and meeting
-- Author: System
-- Date: 2025-01-29

-- First, update any existing tasks with removed task types to review_draft
-- Convert any non-review_draft, non-meeting tasks to review_draft
UPDATE tasks 
SET task_type = 'review_draft'
WHERE task_type NOT IN ('review_draft', 'meeting');

-- Add a temporary text column
ALTER TABLE tasks ADD COLUMN task_type_new TEXT;

-- Copy the data to the temporary column
UPDATE tasks SET task_type_new = task_type::text;

-- Drop the old column and enum
ALTER TABLE tasks DROP COLUMN task_type;
DROP TYPE IF EXISTS task_type CASCADE;

-- Create new enum with only the needed types
CREATE TYPE task_type AS ENUM ('review_draft', 'meeting');

-- Add the new column with the new enum type
ALTER TABLE tasks ADD COLUMN task_type task_type;

-- Update the new column with the data from the temporary column
-- Only set valid values, default to 'review_draft' for any invalid ones
UPDATE tasks SET task_type = 
  CASE 
    WHEN task_type_new IN ('review_draft', 'meeting') THEN task_type_new::task_type
    ELSE 'review_draft'::task_type
  END;

-- Drop the temporary column
ALTER TABLE tasks DROP COLUMN task_type_new;

-- Add comment explaining the simplification
COMMENT ON TYPE task_type IS 'Simplified task types: review_draft for email reviews, meeting for meeting preparation';
COMMENT ON TABLE tasks IS 'Tasks table with simplified task types - only review_draft and meeting supported'; 