-- Migration: Add priority_rank column to tasks table for proper database-level sorting
-- Priority rank: 1=urgent (highest), 2=high, 3=normal, 4=low (lowest)
-- This allows ORDER BY priority_rank ASC to get highest priority first

-- Add the priority_rank column
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS priority_rank INTEGER;

-- Create index for efficient sorting
CREATE INDEX IF NOT EXISTS idx_tasks_priority_rank ON tasks (priority_rank);

-- Create composite index for common query pattern: org_id + status + priority_rank + created_at
CREATE INDEX IF NOT EXISTS idx_tasks_org_status_priority_created ON tasks (organization_id, status, priority_rank, created_at DESC);

-- Backfill existing rows based on priority text value
UPDATE tasks 
SET priority_rank = CASE priority
    WHEN 'urgent' THEN 1
    WHEN 'high' THEN 2
    WHEN 'normal' THEN 3
    WHEN 'low' THEN 4
    ELSE 3  -- Default to 'normal' priority
END
WHERE priority_rank IS NULL;

-- Set default value for new rows
ALTER TABLE tasks ALTER COLUMN priority_rank SET DEFAULT 3;

-- Add NOT NULL constraint after backfill
ALTER TABLE tasks ALTER COLUMN priority_rank SET NOT NULL;

-- Create a trigger function to automatically set priority_rank when priority changes
CREATE OR REPLACE FUNCTION set_task_priority_rank()
RETURNS TRIGGER AS $$
BEGIN
    NEW.priority_rank := CASE NEW.priority
        WHEN 'urgent' THEN 1
        WHEN 'high' THEN 2
        WHEN 'normal' THEN 3
        WHEN 'low' THEN 4
        ELSE 3
    END;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to automatically update priority_rank on insert/update
DROP TRIGGER IF EXISTS trigger_set_task_priority_rank ON tasks;
CREATE TRIGGER trigger_set_task_priority_rank
    BEFORE INSERT OR UPDATE OF priority ON tasks
    FOR EACH ROW
    EXECUTE FUNCTION set_task_priority_rank();

-- Add comment for documentation
COMMENT ON COLUMN tasks.priority_rank IS 'Numeric priority rank for database sorting: 1=urgent, 2=high, 3=normal, 4=low';

