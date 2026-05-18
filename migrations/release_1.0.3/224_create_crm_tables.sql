-- Migration: Create CRM lists and raw records tables
-- Date: 2026-03-24
-- Description: Add CRM functionality for CSV import and list management

-- Create crm_lists table
CREATE TABLE IF NOT EXISTS crm_lists (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
  name text NOT NULL,
  description text,
  source text NOT NULL CHECK (source IN ('csv_import', 'manual', 'campaign_output')),
  row_count integer NOT NULL DEFAULT 0 CHECK (row_count >= 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Create crm_raw_records table
CREATE TABLE IF NOT EXISTS crm_raw_records (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  list_id uuid NOT NULL REFERENCES crm_lists(id) ON DELETE CASCADE,
  organization_id text NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
  raw_data jsonb NOT NULL DEFAULT '{}'::jsonb,
  record_type text NOT NULL DEFAULT 'unknown' CHECK (record_type IN ('company', 'person', 'unknown')),
  extracted_company_id uuid REFERENCES companies(id) ON DELETE SET NULL,
  extracted_person_id uuid REFERENCES contacts(id) ON DELETE SET NULL,
  import_status text NOT NULL DEFAULT 'raw' CHECK (import_status IN ('raw', 'extracted', 'failed')),
  import_error text,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Add indexes for crm_lists
CREATE INDEX IF NOT EXISTS idx_crm_lists_org_id ON crm_lists(organization_id);
CREATE INDEX IF NOT EXISTS idx_crm_lists_source ON crm_lists(source);
CREATE INDEX IF NOT EXISTS idx_crm_lists_created_at ON crm_lists(created_at);

-- Add indexes for crm_raw_records
CREATE INDEX IF NOT EXISTS idx_crm_raw_records_list_id ON crm_raw_records(list_id);
CREATE INDEX IF NOT EXISTS idx_crm_raw_records_org_id ON crm_raw_records(organization_id);
CREATE INDEX IF NOT EXISTS idx_crm_raw_records_import_status ON crm_raw_records(import_status);
CREATE INDEX IF NOT EXISTS idx_crm_raw_records_record_type ON crm_raw_records(record_type);
CREATE INDEX IF NOT EXISTS idx_crm_raw_records_extracted_company_id ON crm_raw_records(extracted_company_id) WHERE extracted_company_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_crm_raw_records_extracted_person_id ON crm_raw_records(extracted_person_id) WHERE extracted_person_id IS NOT NULL;

-- Add trigger to update updated_at timestamp on crm_lists
CREATE OR REPLACE FUNCTION update_crm_lists_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER crm_lists_updated_at
  BEFORE UPDATE ON crm_lists
  FOR EACH ROW
  EXECUTE FUNCTION update_crm_lists_updated_at();

-- Add RLS policies for crm_lists
ALTER TABLE crm_lists ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view CRM lists for their organization" ON crm_lists
  FOR SELECT USING (organization_id = current_setting('app.current_org_id', true));

CREATE POLICY "Users can insert CRM lists for their organization" ON crm_lists
  FOR INSERT WITH CHECK (organization_id = current_setting('app.current_org_id', true));

CREATE POLICY "Users can update CRM lists for their organization" ON crm_lists
  FOR UPDATE USING (organization_id = current_setting('app.current_org_id', true));

CREATE POLICY "Users can delete CRM lists for their organization" ON crm_lists
  FOR DELETE USING (organization_id = current_setting('app.current_org_id', true));

-- Add RLS policies for crm_raw_records
ALTER TABLE crm_raw_records ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view CRM raw records for their organization" ON crm_raw_records
  FOR SELECT USING (organization_id = current_setting('app.current_org_id', true));

CREATE POLICY "Users can insert CRM raw records for their organization" ON crm_raw_records
  FOR INSERT WITH CHECK (organization_id = current_setting('app.current_org_id', true));

CREATE POLICY "Users can update CRM raw records for their organization" ON crm_raw_records
  FOR UPDATE USING (organization_id = current_setting('app.current_org_id', true));

CREATE POLICY "Users can delete CRM raw records for their organization" ON crm_raw_records
  FOR DELETE USING (organization_id = current_setting('app.current_org_id', true));

-- Add comments
COMMENT ON TABLE crm_lists IS 'CRM lists for organizing imported data and campaign outputs';
COMMENT ON COLUMN crm_lists.source IS 'Source of the list: csv_import, manual, or campaign_output';
COMMENT ON COLUMN crm_lists.row_count IS 'Denormalized count of records in the list, updated on import';

COMMENT ON TABLE crm_raw_records IS 'Raw imported data before extraction and processing';
COMMENT ON COLUMN crm_raw_records.raw_data IS 'Original CSV row as JSON object, never transformed at import time';
COMMENT ON COLUMN crm_raw_records.record_type IS 'Type after extraction: company, person, or unknown';
COMMENT ON COLUMN crm_raw_records.import_status IS 'Processing status: raw, extracted, or failed';
COMMENT ON COLUMN crm_raw_records.import_error IS 'Error message if extraction failed';
