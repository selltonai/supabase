-- Migration: Create CRM list members table
-- Description: Adds many-to-many membership for existing CRM contacts and companies.
-- Projects: selltonai-modal writes/reads memberships; selltonai reads through API/UI.
-- Application code: deploy together with CRM list member endpoints and CRM bulk list actions.

CREATE TABLE IF NOT EXISTS crm_list_members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  list_id uuid NOT NULL REFERENCES crm_lists(id) ON DELETE CASCADE,
  organization_id text NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
  company_id uuid REFERENCES companies(id) ON DELETE CASCADE,
  contact_id uuid REFERENCES contacts(id) ON DELETE CASCADE,
  source text NOT NULL DEFAULT 'manual' CHECK (source IN ('manual', 'campaign_selection')),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT crm_list_members_one_entity_check CHECK (
    (company_id IS NOT NULL AND contact_id IS NULL)
    OR (company_id IS NULL AND contact_id IS NOT NULL)
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_crm_list_members_unique_company
  ON crm_list_members(list_id, organization_id, company_id)
  WHERE company_id IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_crm_list_members_unique_contact
  ON crm_list_members(list_id, organization_id, contact_id)
  WHERE contact_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_crm_list_members_list_id
  ON crm_list_members(list_id);

CREATE INDEX IF NOT EXISTS idx_crm_list_members_org_id
  ON crm_list_members(organization_id);

CREATE INDEX IF NOT EXISTS idx_crm_list_members_company_id
  ON crm_list_members(company_id)
  WHERE company_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_crm_list_members_contact_id
  ON crm_list_members(contact_id)
  WHERE contact_id IS NOT NULL;

ALTER TABLE crm_list_members ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view CRM list members for their organization" ON crm_list_members
  FOR SELECT USING (organization_id = current_setting('app.current_org_id', true));

CREATE POLICY "Users can insert CRM list members for their organization" ON crm_list_members
  FOR INSERT WITH CHECK (organization_id = current_setting('app.current_org_id', true));

CREATE POLICY "Users can update CRM list members for their organization" ON crm_list_members
  FOR UPDATE USING (organization_id = current_setting('app.current_org_id', true));

CREATE POLICY "Users can delete CRM list members for their organization" ON crm_list_members
  FOR DELETE USING (organization_id = current_setting('app.current_org_id', true));

COMMENT ON TABLE crm_list_members IS 'Manual memberships linking existing contacts or companies to CRM lists';
COMMENT ON COLUMN crm_list_members.source IS 'How the member was added to the list: manual or campaign_selection';
