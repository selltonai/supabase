-- Add missing values to email_status enum
-- Migration: 221_add_scheduled_to_email_status_enum.sql
-- Release: v1.0.2
-- Reason: Campaign cancellation was failing because 'scheduled' was missing from the enum

-- The complete enum should include all values used by the application:
-- 'draft', 'scheduled', 'sent', 'delivered', 'opened', 'clicked', 'replied', 'bounced', 'failed'

-- Add 'scheduled' value (most critical - causing the current error)
DO $$ 
BEGIN
    ALTER TYPE email_status ADD VALUE 'scheduled';
EXCEPTION 
    WHEN duplicate_object THEN 
        -- Value already exists, which is fine
        NULL; 
END $$;

-- Note on 'pending': This value exists in some old schema definitions but appears
-- to be legacy. The current application uses 'scheduled' instead for emails that
-- are queued to be sent later. If 'pending' emails exist in the database, they
-- should be migrated to 'scheduled' status in a separate data migration.
