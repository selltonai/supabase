-- Migration: Add contact_extraction_limit to organization_settings table
-- Description: Adds a configurable contact extraction limit setting (default 5, range 1-10)
-- Author: System
-- Date: 2025-01-XX

-- Add contact_extraction_limit column to organization_settings table
ALTER TABLE organization_settings 
  ADD COLUMN IF NOT EXISTS contact_extraction_limit INTEGER NOT NULL DEFAULT 5;

-- Add CHECK constraint to ensure value is between 1 and 10 (matching API limits)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conname = 'check_contact_extraction_limit_range'
    AND conrelid = 'organization_settings'::regclass
  ) THEN
    ALTER TABLE organization_settings 
      ADD CONSTRAINT check_contact_extraction_limit_range 
      CHECK (contact_extraction_limit >= 1 AND contact_extraction_limit <= 10);
  END IF;
END $$;

-- Set default value to 5 for existing organizations that might have NULL
UPDATE organization_settings 
  SET contact_extraction_limit = 5 
  WHERE contact_extraction_limit IS NULL OR contact_extraction_limit < 1 OR contact_extraction_limit > 10;

-- Add comment for documentation
COMMENT ON COLUMN organization_settings.contact_extraction_limit IS 'Maximum number of contacts to extract per company (default: 5, range: 1-10)';

