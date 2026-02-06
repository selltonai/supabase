-- Add thread_id and email_id columns to tasks table
-- These columns will store Gmail thread and email identifiers

-- Add thread_id column
ALTER TABLE tasks 
ADD COLUMN IF NOT EXISTS thread_id TEXT;

-- Add email_id column  
ALTER TABLE tasks
ADD COLUMN IF NOT EXISTS email_id TEXT;

-- Add indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_tasks_thread_id ON tasks(thread_id);
CREATE INDEX IF NOT EXISTS idx_tasks_email_id ON tasks(email_id);

-- Add comments for documentation
COMMENT ON COLUMN tasks.thread_id IS 'Gmail thread ID (e.g., "198cc5c419a9ebf2")';
COMMENT ON COLUMN tasks.email_id IS 'Gmail email ID (e.g., "198d0348ceb32ea1")';