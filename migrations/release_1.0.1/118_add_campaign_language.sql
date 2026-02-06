-- Migration: Add Language Column to Campaigns Table
-- Description: Adds language column to campaigns table with default 'en' (English)
-- Author: System
-- Date: 2025-01-30

-- Add language column to campaigns table
ALTER TABLE campaigns 
  ADD COLUMN IF NOT EXISTS language TEXT DEFAULT 'en';

-- Update existing campaigns to have 'en' as default language
UPDATE campaigns 
  SET language = 'en' 
  WHERE language IS NULL;

-- Add NOT NULL constraint after backfilling
ALTER TABLE campaigns 
  ALTER COLUMN language SET NOT NULL;

-- Add index on language for filtering
CREATE INDEX IF NOT EXISTS idx_campaigns_language ON campaigns(language);

-- Add comment to column
COMMENT ON COLUMN campaigns.language IS 'Language code for campaign (en, de, fr, sv). Default is en (English).';

