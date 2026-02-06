-- Migration: Add API key support to organization_settings table
-- This migration adds columns to store organization API keys for external API access

-- Add api_key column (nullable, unique)
ALTER TABLE public.organization_settings
  ADD COLUMN IF NOT EXISTS api_key TEXT UNIQUE;

-- Add api_key_created_at timestamp
ALTER TABLE public.organization_settings
  ADD COLUMN IF NOT EXISTS api_key_created_at TIMESTAMPTZ DEFAULT NULL;

-- Add api_key_info_shown flag to track if user has been informed about API key
ALTER TABLE public.organization_settings
  ADD COLUMN IF NOT EXISTS api_key_info_shown BOOLEAN NOT NULL DEFAULT false;

-- Add index for efficient lookup by API key
CREATE INDEX IF NOT EXISTS idx_organization_settings_api_key 
  ON public.organization_settings(api_key) 
  WHERE api_key IS NOT NULL;

-- Add comments for documentation
COMMENT ON COLUMN public.organization_settings.api_key IS 'Unique API key for organization to access external APIs. Generated securely and stored as plain text for authentication purposes.';
COMMENT ON COLUMN public.organization_settings.api_key_created_at IS 'Timestamp when the API key was first created or last regenerated.';
COMMENT ON COLUMN public.organization_settings.api_key_info_shown IS 'Flag indicating if the user has been informed about the API key feature. Used to show informational notification only once.';







