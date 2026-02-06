-- Migration: Add company_id and reasoning_note to tasks table
-- Description: Adds company_id for linking tasks to companies and reasoning_note for explaining task creation logic
-- Author: System
-- Date: 2025-01-30

-- Add company_id column to tasks table
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS company_id UUID REFERENCES companies(id) ON DELETE SET NULL;

-- Add reasoning_note column to tasks table
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS reasoning_note TEXT;

-- Create index on company_id for performance
CREATE INDEX IF NOT EXISTS idx_tasks_company_id ON tasks(company_id);

-- Update the constraint to include company_id validation
ALTER TABLE tasks DROP CONSTRAINT IF EXISTS tasks_valid_type_refs;
ALTER TABLE tasks ADD CONSTRAINT tasks_valid_type_refs 
  CHECK (
    CASE 
      WHEN task_type = 'review_draft' THEN campaign_id IS NOT NULL
      WHEN task_type = 'meeting' THEN contact_id IS NOT NULL
      ELSE TRUE
    END
  );

-- Add comment explaining the new fields
COMMENT ON COLUMN tasks.company_id IS 'Reference to the company this task is related to';
COMMENT ON COLUMN tasks.reasoning_note IS 'Explanation of why this task was created and the reasoning behind it';
COMMENT ON TABLE tasks IS 'Tasks table with company_id and reasoning_note - supports linking tasks to companies and explaining task creation logic'; 