-- Migration: Add approved_at timestamp to campaign_emails
-- Description: Adds approved_at field to track when emails were approved by users before sending
-- Author: System
-- Date: 2025-01-31

-- Add approved_at column to campaign_emails table
ALTER TABLE campaign_emails 
ADD COLUMN IF NOT EXISTS approved_at TIMESTAMPTZ;

-- Add approved_by_user_id to track who approved it
ALTER TABLE campaign_emails 
ADD COLUMN IF NOT EXISTS approved_by_user_id TEXT;

-- Add index for approved_at
CREATE INDEX IF NOT EXISTS idx_campaign_emails_approved_at ON campaign_emails(approved_at);

-- Add comment for documentation
COMMENT ON COLUMN campaign_emails.approved_at IS 'Timestamp when the email was approved by a user (before actual sending)';
COMMENT ON COLUMN campaign_emails.approved_by_user_id IS 'User ID of the person who approved the email'; 