-- Migration: Add Icypeas email enrichment tracking to contacts table
-- This migration adds columns to track Icypeas email finding requests and responses
-- as a fallback when B2B enrichment and Hunter.io don't return a valid email

-- Add icypeas_email_requested column (boolean flag)
ALTER TABLE public.contacts
  ADD COLUMN IF NOT EXISTS icypeas_email_requested BOOLEAN NOT NULL DEFAULT false;

-- Add icypeas_email_response column (JSONB to store Icypeas API response)
ALTER TABLE public.contacts
  ADD COLUMN IF NOT EXISTS icypeas_email_response JSONB DEFAULT NULL;

-- Add index for efficient filtering of contacts needing Icypeas email enrichment
CREATE INDEX IF NOT EXISTS idx_contacts_icypeas_email_requested 
  ON public.contacts(organization_id, icypeas_email_requested) 
  WHERE icypeas_email_requested = false;

-- Add GIN index for efficient querying of icypeas_email_response JSONB
CREATE INDEX IF NOT EXISTS idx_contacts_icypeas_email_response 
  ON public.contacts USING GIN(icypeas_email_response);

-- Add comments for documentation
COMMENT ON COLUMN public.contacts.icypeas_email_requested IS 'Flag indicating if email enrichment has been requested from Icypeas API for this contact. Set to true when request is sent to prevent duplicate requests. Used as fallback when B2B enrichment and Hunter.io fail.';
COMMENT ON COLUMN public.contacts.icypeas_email_response IS 'Icypeas API response stored as JSONB. Contains email finding results including email address, certainty level, MX records, and metadata.';







