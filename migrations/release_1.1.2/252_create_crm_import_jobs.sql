-- Migration: Create CRM import jobs and bulk raw-record update helpers
-- Date: 2026-05-26
-- Description:
--   Adds durable progress tracking for large CRM CSV imports and RPC helpers
--   that let selltonai-modal update extracted raw-record IDs in batches.
-- Affected projects:
--   - selltonai-modal: writes crm_import_jobs and calls RPC helpers.
--   - selltonai: reads progress via selltonai-modal status endpoints.
-- Deploy together:
--   Deploy this migration before the selltonai-modal import job code.

CREATE TABLE IF NOT EXISTS public.crm_import_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  list_id uuid NOT NULL REFERENCES public.crm_lists(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'queued' CHECK (status IN ('queued', 'importing', 'processing', 'completed', 'failed', 'cancelled')),
  phase text NOT NULL DEFAULT 'queued' CHECK (phase IN ('queued', 'raw_import', 'classification', 'companies', 'contacts', 'relationships', 'finalizing', 'completed', 'failed', 'cancelled')),
  total_rows integer NOT NULL DEFAULT 0 CHECK (total_rows >= 0),
  raw_inserted integer NOT NULL DEFAULT 0 CHECK (raw_inserted >= 0),
  records_classified integer NOT NULL DEFAULT 0 CHECK (records_classified >= 0),
  companies_processed integer NOT NULL DEFAULT 0 CHECK (companies_processed >= 0),
  contacts_processed integer NOT NULL DEFAULT 0 CHECK (contacts_processed >= 0),
  relationships_created integer NOT NULL DEFAULT 0 CHECK (relationships_created >= 0),
  failed_rows integer NOT NULL DEFAULT 0 CHECK (failed_rows >= 0),
  last_error text,
  started_at timestamptz,
  finished_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_crm_import_jobs_org_id ON public.crm_import_jobs(organization_id);
CREATE INDEX IF NOT EXISTS idx_crm_import_jobs_list_id ON public.crm_import_jobs(list_id);
CREATE INDEX IF NOT EXISTS idx_crm_import_jobs_status ON public.crm_import_jobs(status);
CREATE INDEX IF NOT EXISTS idx_crm_import_jobs_updated_at ON public.crm_import_jobs(updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_crm_import_jobs_org_list_updated ON public.crm_import_jobs(organization_id, list_id, updated_at DESC);

CREATE OR REPLACE FUNCTION public.update_crm_import_jobs_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS crm_import_jobs_updated_at ON public.crm_import_jobs;
CREATE TRIGGER crm_import_jobs_updated_at
  BEFORE UPDATE ON public.crm_import_jobs
  FOR EACH ROW
  EXECUTE FUNCTION public.update_crm_import_jobs_updated_at();

ALTER TABLE public.crm_import_jobs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view CRM import jobs for their organization" ON public.crm_import_jobs;
CREATE POLICY "Users can view CRM import jobs for their organization" ON public.crm_import_jobs
  FOR SELECT USING (organization_id = current_setting('app.current_org_id', true));

DROP POLICY IF EXISTS "Users can insert CRM import jobs for their organization" ON public.crm_import_jobs;
CREATE POLICY "Users can insert CRM import jobs for their organization" ON public.crm_import_jobs
  FOR INSERT WITH CHECK (organization_id = current_setting('app.current_org_id', true));

DROP POLICY IF EXISTS "Users can update CRM import jobs for their organization" ON public.crm_import_jobs;
CREATE POLICY "Users can update CRM import jobs for their organization" ON public.crm_import_jobs
  FOR UPDATE USING (organization_id = current_setting('app.current_org_id', true));

DROP POLICY IF EXISTS "Users can delete CRM import jobs for their organization" ON public.crm_import_jobs;
CREATE POLICY "Users can delete CRM import jobs for their organization" ON public.crm_import_jobs
  FOR DELETE USING (organization_id = current_setting('app.current_org_id', true));

CREATE OR REPLACE FUNCTION public.bulk_update_crm_raw_record_company_ids(p_organization_id text, p_updates jsonb)
RETURNS integer AS $$
DECLARE
  updated_count integer;
BEGIN
  WITH update_rows AS (
    SELECT
      (item->>'record_id')::uuid AS record_id,
      (item->>'company_id')::uuid AS company_id
    FROM jsonb_array_elements(p_updates) AS item
    WHERE item ? 'record_id' AND item ? 'company_id'
  )
  UPDATE public.crm_raw_records AS raw
  SET extracted_company_id = update_rows.company_id
  FROM update_rows
  WHERE raw.id = update_rows.record_id
    AND raw.organization_id = p_organization_id;

  GET DIAGNOSTICS updated_count = ROW_COUNT;
  RETURN updated_count;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION public.bulk_update_crm_raw_record_person_ids(p_organization_id text, p_updates jsonb)
RETURNS integer AS $$
DECLARE
  updated_count integer;
BEGIN
  WITH update_rows AS (
    SELECT
      (item->>'record_id')::uuid AS record_id,
      (item->>'person_id')::uuid AS person_id
    FROM jsonb_array_elements(p_updates) AS item
    WHERE item ? 'record_id' AND item ? 'person_id'
  )
  UPDATE public.crm_raw_records AS raw
  SET extracted_person_id = update_rows.person_id
  FROM update_rows
  WHERE raw.id = update_rows.record_id
    AND raw.organization_id = p_organization_id;

  GET DIAGNOSTICS updated_count = ROW_COUNT;
  RETURN updated_count;
END;
$$ LANGUAGE plpgsql;

COMMENT ON TABLE public.crm_import_jobs IS 'Durable progress records for large CRM CSV imports';
COMMENT ON COLUMN public.crm_import_jobs.status IS 'Import job status: queued, importing, processing, completed, failed, or cancelled';
COMMENT ON COLUMN public.crm_import_jobs.phase IS 'Current import phase used by the UI progress indicator';
COMMENT ON FUNCTION public.bulk_update_crm_raw_record_company_ids(text, jsonb) IS 'Batch update extracted company IDs on CRM raw records. p_updates is JSONB array of {record_id, company_id}.';
COMMENT ON FUNCTION public.bulk_update_crm_raw_record_person_ids(text, jsonb) IS 'Batch update extracted person IDs on CRM raw records. p_updates is JSONB array of {record_id, person_id}.';
