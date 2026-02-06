-- Migration: Fix Task Constraints After Task Type Simplification
-- Description: Update constraints to remove references to removed task types
-- Author: System
-- Date: 2025-01-29

-- Drop the existing constraint that references removed task types
ALTER TABLE tasks DROP CONSTRAINT IF EXISTS tasks_valid_type_refs;

-- Add updated constraint with only the supported task types
ALTER TABLE tasks ADD CONSTRAINT tasks_valid_type_refs 
  CHECK (
    CASE 
      WHEN task_type = 'review_draft' THEN campaign_id IS NOT NULL
      WHEN task_type = 'meeting' THEN contact_id IS NOT NULL
      ELSE TRUE
    END
  );

-- Add comment explaining the updated constraint
COMMENT ON CONSTRAINT tasks_valid_type_refs ON tasks IS 'Updated constraint for simplified task types: review_draft requires campaign_id, meeting requires contact_id'; 