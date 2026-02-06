-- Migration: Add Phone Column to Contacts Table
-- Description: Adds phone column to contacts table to support phone number storage
-- Author: System
-- Date: 2025-01-30

-- Add phone column to contacts table if it doesn't exist
ALTER TABLE contacts 
  ADD COLUMN IF NOT EXISTS phone TEXT;

-- Add comment to column
COMMENT ON COLUMN contacts.phone IS 'Contact phone number';















