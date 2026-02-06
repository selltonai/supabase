-- Migration: Cleanup and Fix Company Contacts Relationship
-- Description: Comprehensive cleanup and recreation of company_contacts table with proper data types
-- Author: System
-- Date: 2025-07-15

-- Step 1: Drop any existing problematic constraints and tables
DO $$
DECLARE
  r RECORD;
BEGIN
  -- Drop existing company_contacts table if it exists
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'company_contacts') THEN
    DROP TABLE company_contacts CASCADE;
    RAISE NOTICE 'Dropped existing company_contacts table';
  END IF;
  
  -- Drop any orphaned foreign key constraints that might reference company_contacts
  -- Note: This check will only work if the table exists, so we skip if already dropped
  BEGIN
    FOR r IN (
      SELECT conname, conrelid::regclass AS table_name
      FROM pg_constraint
      WHERE confrelid = 'company_contacts'::regclass::oid
    ) LOOP
      EXECUTE format('ALTER TABLE %s DROP CONSTRAINT IF EXISTS %I', r.table_name, r.conname);
      RAISE NOTICE 'Dropped constraint % on table %', r.conname, r.table_name;
    END LOOP;
  EXCEPTION
    WHEN undefined_table THEN
      RAISE NOTICE 'company_contacts table does not exist, skipping constraint cleanup';
  END;
END $$;

-- Step 2: Ensure the update_updated_at_column function exists
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Step 3: Create company_contacts table with verified data types
CREATE TABLE public.company_contacts (
  id UUID NOT NULL DEFAULT gen_random_uuid(),
  company_id UUID NOT NULL,
  contact_id UUID NOT NULL,
  organization_id TEXT NOT NULL,  -- Explicitly TEXT to match organization.id
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  
  -- Primary key
  CONSTRAINT company_contacts_pkey PRIMARY KEY (id)
);

-- Step 4: Add foreign key constraints with proper error handling
DO $$
BEGIN
  -- Add company_id foreign key
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'companies') THEN
    ALTER TABLE company_contacts 
      ADD CONSTRAINT company_contacts_company_id_fkey 
      FOREIGN KEY (company_id) 
      REFERENCES companies(id) 
      ON DELETE CASCADE;
    RAISE NOTICE 'Added foreign key constraint for company_id';
  END IF;
  
  -- Add contact_id foreign key
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'contacts') THEN
    ALTER TABLE company_contacts 
      ADD CONSTRAINT company_contacts_contact_id_fkey 
      FOREIGN KEY (contact_id) 
      REFERENCES contacts(id) 
      ON DELETE CASCADE;
    RAISE NOTICE 'Added foreign key constraint for contact_id';
  END IF;
  
  -- Add organization_id foreign key
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'organization') THEN
    ALTER TABLE company_contacts 
      ADD CONSTRAINT company_contacts_organization_id_fkey 
      FOREIGN KEY (organization_id) 
      REFERENCES organization(id) 
      ON DELETE CASCADE;
    RAISE NOTICE 'Added foreign key constraint for organization_id';
  END IF;
  
  -- Add unique constraint
  ALTER TABLE company_contacts
    ADD CONSTRAINT company_contacts_unique 
    UNIQUE (company_id, contact_id, organization_id);
  RAISE NOTICE 'Added unique constraint';
  
EXCEPTION
  WHEN others THEN
    RAISE NOTICE 'Error adding constraints: %', SQLERRM;
END $$;

-- Step 5: Create indexes
CREATE INDEX idx_company_contacts_company_id ON company_contacts(company_id);
CREATE INDEX idx_company_contacts_contact_id ON company_contacts(contact_id);
CREATE INDEX idx_company_contacts_organization_id ON company_contacts(organization_id);
CREATE INDEX idx_company_contacts_created_at ON company_contacts(created_at DESC);

-- Step 6: Enable Row Level Security
ALTER TABLE company_contacts ENABLE ROW LEVEL SECURITY;

-- Step 7: Create RLS policies using user_organizations table
CREATE POLICY "Users can view company_contacts in their organization" ON company_contacts
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 
      FROM user_organizations uo
      WHERE uo.user_id = auth.uid()  -- Both are TEXT, no casting needed
      AND uo.organization_id = company_contacts.organization_id
    )
  );

CREATE POLICY "Users can insert company_contacts in their organization" ON company_contacts
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 
      FROM user_organizations uo
      WHERE uo.user_id = auth.uid()
      AND uo.organization_id = company_contacts.organization_id
    )
  );

CREATE POLICY "Users can update company_contacts in their organization" ON company_contacts
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 
      FROM user_organizations uo
      WHERE uo.user_id = auth.uid()
      AND uo.organization_id = company_contacts.organization_id
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 
      FROM user_organizations uo
      WHERE uo.user_id = auth.uid()
      AND uo.organization_id = company_contacts.organization_id
    )
  );

CREATE POLICY "Users can delete company_contacts in their organization" ON company_contacts
  FOR DELETE
  USING (
    EXISTS (
      SELECT 1 
      FROM user_organizations uo
      WHERE uo.user_id = auth.uid()
      AND uo.organization_id = company_contacts.organization_id
    )
  );

-- Step 8: Create trigger for updated_at
CREATE TRIGGER update_company_contacts_updated_at
    BEFORE UPDATE ON company_contacts
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Step 9: Add helpful comments
COMMENT ON TABLE company_contacts IS 'Many-to-many relationship table linking companies to their contacts';
COMMENT ON COLUMN company_contacts.company_id IS 'Reference to the company (UUID)';
COMMENT ON COLUMN company_contacts.contact_id IS 'Reference to the contact (UUID)';
COMMENT ON COLUMN company_contacts.organization_id IS 'Organization that owns this relationship (TEXT)';

-- Step 10: Migrate existing data if applicable
DO $$
DECLARE
  migrated_count INTEGER := 0;
BEGIN
  -- Check if contacts table has a company_id column
  IF EXISTS (
    SELECT 1 
    FROM information_schema.columns 
    WHERE table_name = 'contacts' 
    AND column_name = 'company_id'
  ) THEN
    -- Migrate data with proper error handling
    INSERT INTO company_contacts (company_id, contact_id, organization_id)
    SELECT DISTINCT 
      c.company_id,
      c.id,
      c.organization_id
    FROM contacts c
    INNER JOIN companies comp ON comp.id = c.company_id
    WHERE c.company_id IS NOT NULL
    AND c.organization_id IS NOT NULL
    ON CONFLICT (company_id, contact_id, organization_id) DO NOTHING;
    
    GET DIAGNOSTICS migrated_count = ROW_COUNT;
    RAISE NOTICE 'Successfully migrated % company-contact relationships', migrated_count;
  ELSE
    RAISE NOTICE 'No company_id column found in contacts table, skipping migration';
  END IF;
EXCEPTION
  WHEN others THEN
    RAISE NOTICE 'Error during data migration: %', SQLERRM;
    RAISE NOTICE 'Continuing without data migration';
END $$;

-- Step 11: Verify the table structure
DO $$
DECLARE
  col RECORD;
BEGIN
  RAISE NOTICE 'Company_contacts table structure:';
  FOR col IN 
    SELECT column_name, data_type, is_nullable
    FROM information_schema.columns
    WHERE table_name = 'company_contacts'
    ORDER BY ordinal_position
  LOOP
    RAISE NOTICE '  Column: % (Type: %, Nullable: %)', col.column_name, col.data_type, col.is_nullable;
  END LOOP;
END $$; 