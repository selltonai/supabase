-- Migration: Add feedback column to tasks table
-- Created: 2025-12-15
-- Purpose: Enable like/dislike feedback on tasks for training and quality control
-- This allows users to mark tasks (email drafts, company verifications) as good or bad

-- Add feedback column to tasks table
-- Values: null (no feedback), 'liked', 'disliked'
ALTER TABLE public.tasks 
ADD COLUMN IF NOT EXISTS feedback TEXT DEFAULT NULL;

-- Add check constraint for valid feedback values
ALTER TABLE public.tasks
DROP CONSTRAINT IF EXISTS tasks_feedback_check;

ALTER TABLE public.tasks
ADD CONSTRAINT tasks_feedback_check 
CHECK (feedback IS NULL OR feedback IN ('liked', 'disliked'));

-- Add helpful comment explaining the column
COMMENT ON COLUMN public.tasks.feedback IS 
'User feedback on task quality for training purposes.
Values: null (no feedback), ''liked'' (good quality), ''disliked'' (poor quality).
Used to identify good/bad email copy and company verification quality.';

-- Create index for filtering tasks by feedback
CREATE INDEX IF NOT EXISTS idx_tasks_feedback 
ON public.tasks(feedback) WHERE feedback IS NOT NULL;







