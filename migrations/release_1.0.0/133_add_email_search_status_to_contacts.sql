-- Migration: Add email_search_status column to contacts table
-- Purpose: Track the status of email address search for contacts
-- Date: 2025-01-XX

-- Add email_search_status column to contacts table
ALTER TABLE contacts 
  ADD COLUMN IF NOT EXISTS email_search_status TEXT DEFAULT 'search_not_started' 
  CHECK (email_search_status IN ('search_not_started', 'started_searching_email', 'finished_searching_email'));

-- Create index for performance
CREATE INDEX IF NOT EXISTS idx_contacts_email_search_status ON contacts(email_search_status);

-- Add comment for documentation
COMMENT ON COLUMN contacts.email_search_status IS 'Status of email address search: search_not_started, started_searching_email, finished_searching_email';














