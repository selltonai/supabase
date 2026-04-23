-- Add b2b_enrichment JSONB column to companies table for storing raw B2B enrichment payloads
-- This supports downstream ICP analysis and auditing of enrichment data

ALTER TABLE public.companies
ADD COLUMN IF NOT EXISTS b2b_enrichment JSONB;

COMMENT ON COLUMN public.companies.b2b_enrichment IS 'Raw B2B enrichment payload (profile/analysis/activities) for detailed ICP analysis and auditing';

