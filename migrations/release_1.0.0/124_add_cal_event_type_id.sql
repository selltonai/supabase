-- Migration: Add Cal.com event type ID to organization settings
-- Purpose: Store the Cal.com event type ID along with the API key for meeting scheduling
-- Date: 2025-01-21

-- Update the api_credentials JSONB column to include cal_com_event_type_id
-- This will update the default value for new rows and existing rows that have the default structure
UPDATE organization_settings
SET api_credentials = jsonb_set(
  COALESCE(api_credentials, '{}'::jsonb),
  '{cal_com_event_type_id}',
  '""'::jsonb,
  true
)
WHERE NOT (api_credentials ? 'cal_com_event_type_id');

-- Add a comment to document the new field
COMMENT ON COLUMN organization_settings.api_credentials IS 'API credentials for calendar integrations (Cal.com with API key and event type ID, Calendly)';
