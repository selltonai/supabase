-- Migration: Add provider_responses column to contacts table
-- This migration adds a JSONB column to store email enrichment provider responses
-- for tracking and debugging email finding attempts

-- Add provider_responses column (JSONB to store provider responses)
ALTER TABLE public.contacts
  ADD COLUMN IF NOT EXISTS provider_responses JSONB DEFAULT NULL;

-- Add GIN index for efficient querying of provider_responses JSONB
CREATE INDEX IF NOT EXISTS idx_contacts_provider_responses
  ON public.contacts USING GIN(provider_responses);

-- Add comment for documentation
COMMENT ON COLUMN public.contacts.provider_responses IS 'JSONB storage for email enrichment provider responses. Contains responses from various email finding services (Hunter.io, etc.) for tracking and debugging purposes.';













