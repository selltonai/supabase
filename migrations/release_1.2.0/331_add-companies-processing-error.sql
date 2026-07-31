-- Migration: Add companies processing error details
-- Date: 2026-07-02
-- Description:
--   Adds a durable error message column used when Modal marks a company as
--   failed or reschedules stuck processing work.
-- Affected services:
--   selltonai-modal writes this field from campaign auto-reload and company
--   processing recovery paths. selltonai/backoffice may read it for debugging.

ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS processing_error TEXT;

COMMENT ON COLUMN public.companies.processing_error IS
  'Last processing failure or recovery reason recorded by campaign/company processing jobs.';
