-- Migration: Add Hunter.io email enrichment tracking to contacts table
-- This migration adds columns to track Hunter.io email finding requests and responses
-- as a fallback when B2B enrichment doesn't return a valid email

-- Add hunter_email_requested column (boolean flag)
ALTER TABLE public.contacts
  ADD COLUMN IF NOT EXISTS hunter_email_requested BOOLEAN NOT NULL DEFAULT false;

-- Add hunter_email_response column (JSONB to store Hunter.io API response)
ALTER TABLE public.contacts
  ADD COLUMN IF NOT EXISTS hunter_email_response JSONB DEFAULT NULL;

-- Add index for efficient filtering of contacts needing Hunter.io email enrichment
CREATE INDEX IF NOT EXISTS idx_contacts_hunter_email_requested 
  ON public.contacts(organization_id, hunter_email_requested) 
  WHERE hunter_email_requested = false;

-- Add GIN index for efficient querying of hunter_email_response JSONB
CREATE INDEX IF NOT EXISTS idx_contacts_hunter_email_response 
  ON public.contacts USING GIN(hunter_email_response);

-- Add comments for documentation
COMMENT ON COLUMN public.contacts.hunter_email_requested IS 'Flag indicating if email enrichment has been requested from Hunter.io API for this contact. Set to true when request is sent to prevent duplicate requests. Used as fallback when B2B enrichment fails.';
COMMENT ON COLUMN public.contacts.hunter_email_response IS 'Hunter.io API response stored as JSONB. Contains email finding results including email address, score, verification status, and metadata.';

