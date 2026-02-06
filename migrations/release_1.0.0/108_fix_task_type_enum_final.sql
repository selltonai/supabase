-- Migration: Final Fix for Task Type Enum
-- Description: Completely drop and recreate task_type enum to fix any OID issues
-- Author: System
-- Date: 2025-01-29

-- First, drop only the task-specific triggers
DROP TRIGGER IF EXISTS validate_task_contact_on_insert ON tasks;
DROP TRIGGER IF EXISTS validate_task_contact_on_update ON tasks;

-- Drop only the task-specific function
DROP FUNCTION IF EXISTS validate_task_contact();

-- Add a temporary text column
ALTER TABLE tasks ADD COLUMN task_type_new TEXT;

-- Copy the data to the temporary column, converting any invalid values to 'review_draft'
UPDATE tasks SET task_type_new = 
  CASE 
    WHEN task_type::text IN ('review_draft', 'meeting') THEN task_type::text
    ELSE 'review_draft'
  END;

-- Drop the old column and enum completely
ALTER TABLE tasks DROP COLUMN task_type;
DROP TYPE IF EXISTS task_type CASCADE;

-- Create new enum with only the valid types
CREATE TYPE task_type AS ENUM ('review_draft', 'meeting');

-- Add the new column with the new enum type
ALTER TABLE tasks ADD COLUMN task_type task_type;

-- Update the new column with the data from the temporary column
UPDATE tasks SET task_type = task_type_new::task_type;

-- Drop the temporary column
ALTER TABLE tasks DROP COLUMN task_type_new;

-- Recreate only the task-specific function
CREATE OR REPLACE FUNCTION validate_task_contact()
RETURNS TRIGGER AS $$
BEGIN
    -- Validate that contact belongs to the same organization
    IF NEW.contact_id IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1 FROM contacts 
            WHERE id = NEW.contact_id 
            AND organization_id = NEW.organization_id
        ) THEN
            RAISE EXCEPTION 'Contact does not belong to the same organization';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Recreate only the task-specific triggers
CREATE TRIGGER validate_task_contact_on_insert 
    BEFORE INSERT ON tasks 
    FOR EACH ROW 
    EXECUTE FUNCTION validate_task_contact();

CREATE TRIGGER validate_task_contact_on_update 
    BEFORE UPDATE ON tasks 
    FOR EACH ROW 
    WHEN (NEW.contact_id IS DISTINCT FROM OLD.contact_id)
    EXECUTE FUNCTION validate_task_contact();

-- Add the constraint back
ALTER TABLE tasks ADD CONSTRAINT tasks_valid_type_refs 
  CHECK (
    CASE 
      WHEN task_type = 'review_draft' THEN campaign_id IS NOT NULL
      WHEN task_type = 'meeting' THEN contact_id IS NOT NULL
      ELSE TRUE
    END
  );

-- Add comment
COMMENT ON TYPE task_type IS 'Task types: review_draft for email reviews, meeting for meeting preparation'; 