-- Migration: Add sensitive data detection columns to organization_files
-- Description: Adds columns to track if documents contain sensitive information detected by Vector API screening

-- Add has_sensitive_data column (boolean flag)
ALTER TABLE public.organization_files
  ADD COLUMN IF NOT EXISTS has_sensitive_data BOOLEAN DEFAULT false;

-- Add sensitive_data_types column (array of strings)
ALTER TABLE public.organization_files
  ADD COLUMN IF NOT EXISTS sensitive_data_types TEXT[] DEFAULT '{}'::text[];

-- Add index for filtering files with sensitive data
CREATE INDEX IF NOT EXISTS idx_organization_files_has_sensitive_data 
  ON public.organization_files(organization_id, has_sensitive_data) 
  WHERE has_sensitive_data = true;

-- Add comments for documentation
COMMENT ON COLUMN public.organization_files.has_sensitive_data IS 'Flag indicating if sensitive information (PII, financial data, etc.) was detected in this document during screening';
COMMENT ON COLUMN public.organization_files.sensitive_data_types IS 'Array of sensitive data types detected (e.g., email, phone, ssn, credit_card, api_key, etc.)';

