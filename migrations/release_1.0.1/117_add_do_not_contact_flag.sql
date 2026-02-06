-- Migration: Add do_not_contact flag to contacts table
-- Description: Adds a boolean flag to mark contacts that should not be contacted
-- Author: System
-- Date: 2025-01-XX

-- Add do_not_contact column to contacts table
ALTER TABLE contacts 
  ADD COLUMN IF NOT EXISTS do_not_contact BOOLEAN NOT NULL DEFAULT false;

-- Add index for efficient filtering
CREATE INDEX IF NOT EXISTS idx_contacts_do_not_contact 
  ON contacts(do_not_contact) 
  WHERE do_not_contact = true;

-- Add comment for documentation
COMMENT ON COLUMN contacts.do_not_contact IS 'Flag to mark contacts that should not be contacted. When true, all email communication is blocked and tasks are deleted.';
















