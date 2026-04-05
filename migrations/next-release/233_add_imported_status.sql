-- Migration: Add 'imported' processing_status to companies and contacts tables
-- Purpose: Allow CRM imported records to have distinct status from campaign-processed records
-- Date: 2026-04-04

-- Update companies processing_status constraint to include 'imported'
ALTER TABLE public.companies 
  DROP CONSTRAINT IF EXISTS companies_processing_status_check;

ALTER TABLE public.companies 
  ADD CONSTRAINT companies_processing_status_check 
  CHECK (processing_status = ANY (ARRAY[
    'pending'::text, 
    'scheduled'::text, 
    'processing'::text, 
    'processed'::text, 
    'approved'::text, 
    'declined'::text, 
    'failed'::text, 
    'blocked_by_icp'::text,
    'imported'::text
  ]));

-- Update contacts processing_status constraint to include 'imported'
ALTER TABLE public.contacts 
  DROP CONSTRAINT IF EXISTS contacts_processing_status_check;

ALTER TABLE public.contacts 
  ADD CONSTRAINT contacts_processing_status_check 
  CHECK (processing_status = ANY (ARRAY[
    'pending'::text, 
    'processing'::text, 
    'completed'::text, 
    'failed'::text,
    'imported'::text
  ]));

-- Add comment explaining the new status
COMMENT ON COLUMN public.companies.processing_status IS 'Status of company data processing. Flow: pending → processing → processed → (approved OR declined OR blocked_by_icp). For CRM imports: imported. Valid values: pending, scheduled, processing, processed, approved, declined, failed, blocked_by_icp, imported';

COMMENT ON COLUMN public.contacts.processing_status IS 'Status of contact data processing. Values: pending, processing, completed, failed, imported (for CRM imports)';
