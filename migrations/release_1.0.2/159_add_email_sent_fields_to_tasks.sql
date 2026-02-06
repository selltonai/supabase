-- Migration: Add email sent tracking fields to tasks table
-- Description: Adds sent_at timestamp and scheduled boolean columns to track when emails are sent/scheduled
-- Date: 2025-11-17

-- Add sent_at column to track when email was/will be sent
ALTER TABLE public.tasks
ADD COLUMN IF NOT EXISTS sent_at timestamp with time zone NULL;

-- Add scheduled column to indicate if email was scheduled
ALTER TABLE public.tasks
ADD COLUMN IF NOT EXISTS scheduled boolean NOT NULL DEFAULT false;

-- Add comment to explain the columns
COMMENT ON COLUMN public.tasks.sent_at IS 'Timestamp when email was sent (immediate) or will be sent (scheduled). Used for follow-up timing calculations.';
COMMENT ON COLUMN public.tasks.scheduled IS 'Indicates whether the email was scheduled for future delivery (true) or sent immediately (false).';

-- Create index on sent_at for efficient querying of sent emails
CREATE INDEX IF NOT EXISTS idx_tasks_sent_at ON public.tasks(organization_id, sent_at)
WHERE sent_at IS NOT NULL;

-- Create index on scheduled for filtering scheduled emails
CREATE INDEX IF NOT EXISTS idx_tasks_scheduled ON public.tasks(organization_id, scheduled)
WHERE scheduled = true;

-- Note: gmail_response will remain in metadata.jsonb as it's a large JSON object
-- and is mainly used for reference/debugging purposes

