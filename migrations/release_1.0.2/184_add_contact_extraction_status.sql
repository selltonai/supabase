-- Migration: Add contact_extraction_status column to companies table
-- This tracks the status of contact extraction for each company

-- Add the column with default value
ALTER TABLE public.companies 
ADD COLUMN IF NOT EXISTS contact_extraction_status TEXT DEFAULT 'extraction_not_started';

-- Add comment
COMMENT ON COLUMN public.companies.contact_extraction_status IS 'Status of contact extraction: extraction_not_started, extracting_contacts, extraction_complete';

-- Create index for filtering by extraction status
CREATE INDEX IF NOT EXISTS idx_companies_contact_extraction_status 
ON public.companies(contact_extraction_status) 
WHERE contact_extraction_status IS NOT NULL;

