-- Migration: Create crm_column_mappings table
-- Purpose: Store user-confirmed CSV-to-DB column mappings for CRM import
-- When a user maps CSV columns to database fields, save the mapping so future
-- imports with the same CSV structure auto-apply the saved mapping.
-- Date: 2026-04-06

CREATE TABLE IF NOT EXISTS crm_column_mappings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
  name text NOT NULL DEFAULT 'Default',
  csv_pattern text NOT NULL,
  csv_headers text[] NOT NULL DEFAULT '{}'::text[],
  company_mappings jsonb NOT NULL DEFAULT '{}'::jsonb,
  contact_mappings jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Index for fast lookup by org + csv pattern
CREATE INDEX IF NOT EXISTS idx_crm_column_mappings_org_pattern ON crm_column_mappings(organization_id, csv_pattern);

-- Index for listing all mappings for an org
CREATE INDEX IF NOT EXISTS idx_crm_column_mappings_org_id ON crm_column_mappings(organization_id);

-- RLS
ALTER TABLE crm_column_mappings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view CRM column mappings for their organization" ON crm_column_mappings
  FOR SELECT USING (organization_id = current_setting('app.current_org_id', true));

CREATE POLICY "Users can insert CRM column mappings for their organization" ON crm_column_mappings
  FOR INSERT WITH CHECK (organization_id = current_setting('app.current_org_id', true));

CREATE POLICY "Users can update CRM column mappings for their organization" ON crm_column_mappings
  FOR UPDATE USING (organization_id = current_setting('app.current_org_id', true));

CREATE POLICY "Users can delete CRM column mappings for their organization" ON crm_column_mappings
  FOR DELETE USING (organization_id = current_setting('app.current_org_id', true));

-- Trigger for updated_at
CREATE OR REPLACE FUNCTION update_crm_column_mappings_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER crm_column_mappings_updated_at
  BEFORE UPDATE ON crm_column_mappings
  FOR EACH ROW
  EXECUTE FUNCTION update_crm_column_mappings_updated_at();

-- Comments
COMMENT ON TABLE crm_column_mappings IS 'Saved CSV-to-DB column mappings for CRM import. csv_pattern is a hash of sorted CSV headers for matching future imports with the same structure.';
COMMENT ON COLUMN crm_column_mappings.csv_pattern IS 'Hash of sorted CSV headers used to match future imports with the same column structure';
COMMENT ON COLUMN crm_column_mappings.csv_headers IS 'Original CSV header names in order, for display in the mapper UI';
COMMENT ON COLUMN crm_column_mappings.company_mappings IS 'Mapping of CSV column names to companies table fields, e.g. {"Company Name": "name", "Website": "website"}';
COMMENT ON COLUMN crm_column_mappings.contact_mappings IS 'Mapping of CSV column names to contacts table fields, e.g. {"First Name": "firstname", "Email": "email"}';
