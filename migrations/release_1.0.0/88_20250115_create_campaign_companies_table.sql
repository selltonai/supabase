-- Migration: Create Campaign Companies Relationship Table
-- Description: Creates a simple many-to-many relationship table between campaigns and companies
-- Author: System
-- Date: 2025-01-15

-- Create campaign_companies table with only essential fields
CREATE TABLE IF NOT EXISTS campaign_companies (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    campaign_id UUID NOT NULL REFERENCES campaigns(id) ON DELETE CASCADE,
    company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
    organization_id TEXT NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Ensure unique campaign-company pairs
    UNIQUE(campaign_id, company_id)
);

-- Create index for performance
CREATE INDEX IF NOT EXISTS idx_campaign_companies_campaign_id ON campaign_companies(campaign_id);
CREATE INDEX IF NOT EXISTS idx_campaign_companies_company_id ON campaign_companies(company_id);
CREATE INDEX IF NOT EXISTS idx_campaign_companies_organization_id ON campaign_companies(organization_id);

-- Enable RLS
ALTER TABLE campaign_companies ENABLE ROW LEVEL SECURITY;

-- Create RLS policies (drop existing ones first)
DROP POLICY IF EXISTS "Users can view campaign companies for their organization" ON campaign_companies;
DROP POLICY IF EXISTS "Users can insert campaign companies for their organization" ON campaign_companies;
DROP POLICY IF EXISTS "Users can update campaign companies for their organization" ON campaign_companies;
DROP POLICY IF EXISTS "Users can delete campaign companies for their organization" ON campaign_companies;

CREATE POLICY "Users can view campaign companies for their organization" ON campaign_companies
    FOR SELECT USING (organization_id = auth.jwt() ->> 'organization_id');

CREATE POLICY "Users can insert campaign companies for their organization" ON campaign_companies
    FOR INSERT WITH CHECK (organization_id = auth.jwt() ->> 'organization_id');

CREATE POLICY "Users can update campaign companies for their organization" ON campaign_companies
    FOR UPDATE USING (organization_id = auth.jwt() ->> 'organization_id');

CREATE POLICY "Users can delete campaign companies for their organization" ON campaign_companies
    FOR DELETE USING (organization_id = auth.jwt() ->> 'organization_id');

-- Create trigger to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_campaign_companies_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop existing trigger if it exists, then create new one
DROP TRIGGER IF EXISTS update_campaign_companies_updated_at ON campaign_companies;
CREATE TRIGGER update_campaign_companies_updated_at
    BEFORE UPDATE ON campaign_companies
    FOR EACH ROW
    EXECUTE FUNCTION update_campaign_companies_updated_at(); 