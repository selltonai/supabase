-- =====================================================
-- Restore send_status Column to Tasks Table
-- =====================================================
-- This migration restores the send_status column that was removed in 179.
-- The frontend EmailCopyTaskUpdater still uses this field to track email sending state.
--
-- send_status values:
--   - 'not_sent': Email has not been sent yet (default)
--   - 'sending': Email is currently being sent
--   - 'sent_success': Email was sent successfully
--   - 'sent_failed': Email send failed
--
-- NOTE: This is different from the task 'status' field which tracks the task lifecycle:
--   - pending, in_review, approved, rejected, completed, etc.
--
-- The send_status specifically tracks the email delivery state.
-- =============================================================================

-- Add send_status column back to tasks table
ALTER TABLE public.tasks
ADD COLUMN IF NOT EXISTS send_status text DEFAULT 'not_sent';

-- Add send_error_message column for failed sends
ALTER TABLE public.tasks
ADD COLUMN IF NOT EXISTS send_error_message text;

-- Add check constraint for send_status values
-- First drop if exists (in case of re-run)
ALTER TABLE public.tasks DROP CONSTRAINT IF EXISTS tasks_send_status_check;

-- Add the constraint
ALTER TABLE public.tasks
ADD CONSTRAINT tasks_send_status_check 
CHECK (send_status IS NULL OR send_status IN ('not_sent', 'sending', 'sent_success', 'sent_failed'));

-- Add comment for documentation
COMMENT ON COLUMN public.tasks.send_status IS 'Email send status: not_sent (default), sending, sent_success, sent_failed. Used by frontend to track email delivery state.';
COMMENT ON COLUMN public.tasks.send_error_message IS 'Error message if email send failed';

-- Create index for querying by send_status (useful for dashboards and monitoring)
CREATE INDEX IF NOT EXISTS idx_tasks_send_status 
ON public.tasks(organization_id, send_status)
WHERE send_status IS NOT NULL;

-- Create index for finding failed emails to retry
CREATE INDEX IF NOT EXISTS idx_tasks_send_status_failed
ON public.tasks(organization_id, send_status, updated_at)
WHERE send_status = 'sent_failed';

-- Backfill existing completed tasks that have sent_at to 'sent_success'
-- These are tasks that were sent before the column was added back
UPDATE public.tasks
SET send_status = 'sent_success'
WHERE sent_at IS NOT NULL 
  AND status = 'completed'
  AND (send_status IS NULL OR send_status = 'not_sent');

-- Log completion
DO $$
BEGIN
    RAISE NOTICE '✅ Restored send_status column to tasks table';
    RAISE NOTICE '✅ Backfilled existing completed tasks with sent_at to sent_success';
END $$;




