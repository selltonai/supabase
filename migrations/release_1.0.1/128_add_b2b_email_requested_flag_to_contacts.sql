-- Migration: Add b2b_email_requested flag to contacts table
-- This flag tracks whether we've already requested email enrichment from B2B API
-- to prevent duplicate email finding requests

-- Add b2b_email_requested column (boolean flag)
ALTER TABLE public.contacts
  ADD COLUMN IF NOT EXISTS b2b_email_requested BOOLEAN DEFAULT false;

-- Add index for efficient filtering of contacts needing email enrichment
CREATE INDEX IF NOT EXISTS idx_contacts_b2b_email_requested 
  ON public.contacts(organization_id, b2b_email_requested) 
  WHERE b2b_email_requested = false;

-- Add comment for documentation
COMMENT ON COLUMN public.contacts.b2b_email_requested IS 'Flag indicating if email enrichment has been requested from B2B API for this contact. Set to true when request is sent to prevent duplicate requests.';

