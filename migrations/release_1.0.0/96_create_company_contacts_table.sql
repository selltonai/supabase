-- Standalone SQL to create company_contacts table
-- This follows the exact same pattern as campaign_companies

-- Drop existing table if it exists
DROP TABLE IF EXISTS public.company_contacts CASCADE;

-- Create the update function if it doesn't exist
CREATE OR REPLACE FUNCTION update_company_contacts_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create the table
CREATE TABLE public.company_contacts (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL,
  contact_id uuid NOT NULL,
  organization_id text NOT NULL,
  created_at timestamp with time zone NULL DEFAULT now(),
  updated_at timestamp with time zone NULL DEFAULT now(),
  CONSTRAINT company_contacts_pkey PRIMARY KEY (id),
  CONSTRAINT company_contacts_company_id_contact_id_key UNIQUE (company_id, contact_id),
  CONSTRAINT company_contacts_company_id_fkey FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE,
  CONSTRAINT company_contacts_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES contacts (id) ON DELETE CASCADE,
  CONSTRAINT company_contacts_organization_id_fkey FOREIGN KEY (organization_id) REFERENCES organization (id) ON DELETE CASCADE
) TABLESPACE pg_default;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_company_contacts_company_id ON public.company_contacts USING btree (company_id) TABLESPACE pg_default;
CREATE INDEX IF NOT EXISTS idx_company_contacts_contact_id ON public.company_contacts USING btree (contact_id) TABLESPACE pg_default;
CREATE INDEX IF NOT EXISTS idx_company_contacts_organization_id ON public.company_contacts USING btree (organization_id) TABLESPACE pg_default;

-- Create trigger
CREATE TRIGGER update_company_contacts_updated_at BEFORE
UPDATE ON company_contacts FOR EACH ROW
EXECUTE FUNCTION update_company_contacts_updated_at(); 