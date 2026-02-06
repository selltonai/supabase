-- Migration: Add Default Campaign Language to Organization Settings
-- Description: Adds default_campaign_language column to organization_settings table with default 'en' (English)
-- Author: System
-- Date: 2025-01-30

-- Add default_campaign_language column to organization_settings table
ALTER TABLE organization_settings 
  ADD COLUMN IF NOT EXISTS default_campaign_language TEXT DEFAULT 'en';

-- Update existing organization settings to have 'en' as default language
UPDATE organization_settings 
  SET default_campaign_language = 'en' 
  WHERE default_campaign_language IS NULL;

-- Add comment to column
COMMENT ON COLUMN organization_settings.default_campaign_language IS 'Default language code for new campaigns (en, de, fr, sv). Default is en (English).';

