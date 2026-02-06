-- Migration: Consolidate email_copy_tasks into tasks table
-- Description: Add missing email-specific fields to tasks table and migrate data from email_copy_tasks
-- This allows us to use a single tasks table for all task types including email drafts
-- Date: 2025-11-25

-- =============================================================================
-- PART 1: Add missing columns to tasks table from email_copy_tasks
-- =============================================================================

-- Add subject column for email tasks
ALTER TABLE public.tasks
ADD COLUMN IF NOT EXISTS subject text;

COMMENT ON COLUMN public.tasks.subject IS 'Email subject line for email-related tasks';

-- Add body column for email tasks (email_copy_tasks had separate subject/body, tasks had pre_generated_copy)
ALTER TABLE public.tasks
ADD COLUMN IF NOT EXISTS body text;

COMMENT ON COLUMN public.tasks.body IS 'Email body content for email-related tasks';

-- Add send_status to track email sending state
ALTER TABLE public.tasks
ADD COLUMN IF NOT EXISTS send_status text DEFAULT 'not_sent';

-- Add check constraint for send_status values
ALTER TABLE public.tasks
DROP CONSTRAINT IF EXISTS tasks_send_status_check;

ALTER TABLE public.tasks
ADD CONSTRAINT tasks_send_status_check 
CHECK (send_status IS NULL OR send_status IN ('not_sent', 'sending', 'sent_success', 'sent_failed'));

COMMENT ON COLUMN public.tasks.send_status IS 'Email send status: not_sent, sending, sent_success, sent_failed';

-- Add send_error_message for failed sends
ALTER TABLE public.tasks
ADD COLUMN IF NOT EXISTS send_error_message text;

COMMENT ON COLUMN public.tasks.send_error_message IS 'Error message when email send fails';

-- Add generation_log for comprehensive email generation logging
ALTER TABLE public.tasks
ADD COLUMN IF NOT EXISTS generation_log jsonb DEFAULT '{}'::jsonb;

COMMENT ON COLUMN public.tasks.generation_log IS 'Comprehensive logging of email generation process including all steps, inputs, outputs, models used, templates, context data, and any errors';

-- =============================================================================
-- PART 2: Make created_by_user_id nullable for automated/cron tasks
-- =============================================================================

-- Allow null created_by_user_id for automated tasks (cron jobs, etc.)
ALTER TABLE public.tasks
ALTER COLUMN created_by_user_id DROP NOT NULL;

COMMENT ON COLUMN public.tasks.created_by_user_id IS 'User who created the task. NULL for automated/cron-generated tasks.';

-- =============================================================================
-- PART 3: Add indexes for new columns
-- =============================================================================

-- Index for querying by send_status
CREATE INDEX IF NOT EXISTS idx_tasks_send_status 
ON public.tasks(organization_id, send_status)
WHERE send_status IS NOT NULL;

-- Index for generation_log queries
CREATE INDEX IF NOT EXISTS idx_tasks_generation_log 
ON public.tasks USING GIN (generation_log);

-- Index for subject searches
CREATE INDEX IF NOT EXISTS idx_tasks_subject 
ON public.tasks(organization_id, subject)
WHERE subject IS NOT NULL;

-- =============================================================================
-- PART 4: Migrate existing data from email_copy_tasks to tasks
-- =============================================================================

-- Insert email_copy_tasks records into tasks table
-- Map fields appropriately and set task_type to 'review_draft'
-- NOTE: body goes to pre_generated_copy because frontend reads pre_generated_copy
INSERT INTO public.tasks (
    id,
    organization_id,
    created_by_user_id,
    title,
    description,
    task_type,
    status,
    priority,
    contact_id,
    company_id,
    campaign_id,
    thread_id,
    subject,
    pre_generated_copy,
    reasoning_note,
    send_status,
    send_error_message,
    sent_at,
    scheduled,
    generation_log,
    metadata,
    created_at,
    updated_at
)
SELECT 
    ect.id,
    ect.organization_id,
    NULL, -- created_by_user_id is NULL for automated tasks
    COALESCE(ect.subject, 'Email Draft'), -- title from subject
    'Migrated from email_copy_tasks', -- description
    'review_draft'::task_type, -- task_type
    CASE 
        WHEN ect.status = 'sent' THEN 'completed'
        WHEN ect.status = 'approved' THEN 'completed'
        WHEN ect.status = 'rejected' THEN 'rejected'
        WHEN ect.status = 'pending' THEN 'pending'
        WHEN ect.status = 'in_review' THEN 'in_review'
        ELSE 'pending'
    END::task_status, -- status mapping
    ect.priority,
    ect.contact_id,
    ect.company_id,
    ect.campaign_id,
    ect.thread_id,
    ect.subject,
    ect.body, -- body from email_copy_tasks goes to pre_generated_copy
    ect.reasoning_note,
    ect.send_status,
    ect.send_error_message,
    ect.sent_at,
    CASE WHEN ect.sent_at IS NOT NULL AND ect.send_status = 'sent_success' THEN false ELSE false END, -- scheduled
    COALESCE(ect.generation_log, '{}'::jsonb),
    COALESCE(ect.metadata, '{}'::jsonb),
    ect.created_at,
    ect.updated_at
FROM public.email_copy_tasks ect
WHERE NOT EXISTS (
    -- Don't insert if task with same ID already exists
    SELECT 1 FROM public.tasks t WHERE t.id = ect.id
)
-- Only insert records where the contact still exists (skip orphaned records)
AND EXISTS (
    SELECT 1 FROM public.contacts c WHERE c.id = ect.contact_id
)
-- Only insert records where the company still exists (if company_id is set)
AND (ect.company_id IS NULL OR EXISTS (
    SELECT 1 FROM public.companies co WHERE co.id = ect.company_id
))
-- Only insert records where the campaign still exists (if campaign_id is set)
AND (ect.campaign_id IS NULL OR EXISTS (
    SELECT 1 FROM public.campaigns ca WHERE ca.id = ect.campaign_id
));

-- =============================================================================
-- PART 5: Ensure pre_generated_copy is populated for all review_draft tasks
-- =============================================================================

-- Copy body to pre_generated_copy for tasks that have body but no pre_generated_copy
-- (for any tasks created with old backend code that saved to body)
UPDATE public.tasks
SET pre_generated_copy = body
WHERE pre_generated_copy IS NULL 
  AND body IS NOT NULL
  AND task_type = 'review_draft';

-- Also copy pre_generated_copy to body for backwards compatibility
UPDATE public.tasks
SET body = pre_generated_copy
WHERE body IS NULL 
  AND pre_generated_copy IS NOT NULL
  AND task_type = 'review_draft';

-- =============================================================================
-- PART 6: Log migration results
-- =============================================================================

DO $$
DECLARE
    migrated_count INTEGER;
    total_email_copy_tasks INTEGER;
BEGIN
    SELECT COUNT(*) INTO total_email_copy_tasks FROM public.email_copy_tasks;
    SELECT COUNT(*) INTO migrated_count FROM public.tasks WHERE description = 'Migrated from email_copy_tasks';
    
    RAISE NOTICE 'Migration complete: % of % email_copy_tasks migrated to tasks table', migrated_count, total_email_copy_tasks;
END $$;

-- =============================================================================
-- NOTE: email_copy_tasks table is NOT dropped in this migration
-- Once backend code is updated to use tasks table, run a separate migration
-- to drop the email_copy_tasks table after verifying everything works
-- =============================================================================

