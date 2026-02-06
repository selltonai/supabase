-- Migration: Add processing_log column to companies table
-- Description: Adds a JSONB column to store detailed processing logs including all checks, reasoning, LLM outputs, and decisions
-- Date: 2025-11-18

ALTER TABLE public.companies
ADD COLUMN IF NOT EXISTS processing_log jsonb DEFAULT NULL;

COMMENT ON COLUMN public.companies.processing_log IS 'Detailed log of company processing including B2B enrichment, deep research, ICP scoring, blocking decisions, and LLM outputs. Stored as JSONB for queryability.';

CREATE INDEX IF NOT EXISTS idx_companies_processing_log ON public.companies USING gin(processing_log);

