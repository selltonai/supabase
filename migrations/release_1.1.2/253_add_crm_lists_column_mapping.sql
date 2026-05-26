-- Migration: Add persisted CRM list column mapping
-- Date: 2026-05-26
-- Description:
--   Stores the exact CSV column mapping used for a CRM list import so the
--   detached Modal worker can honor skipped/contact/company fields during
--   asynchronous extraction.
-- Affected projects:
--   - selltonai-modal: writes and reads crm_lists.column_mapping.
--   - selltonai: sends explicit mappings from the import dialog.
-- Deploy together:
--   Apply before running large CRM CSV imports with the detached worker.

ALTER TABLE public.crm_lists
ADD COLUMN IF NOT EXISTS column_mapping jsonb;

COMMENT ON COLUMN public.crm_lists.column_mapping IS 'CSV source header to CRM import field mapping used by detached CRM import extraction workers.';
