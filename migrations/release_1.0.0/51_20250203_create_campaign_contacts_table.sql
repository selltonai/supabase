-- Migration: Create Campaign Contacts Table
-- Description: Creates a table to track the relationship between campaigns and contacts, including CSV import details
-- Author: System
-- Date: 2025-02-03

-- Create campaign_contacts table to track campaign-contact relationships
CREATE TABLE IF NOT EXISTS campaign_contacts (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    campaign_id UUID NOT NULL REFERENCES campaigns(id) ON DELETE CASCADE,
    contact_id UUID NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,
    organization_id TEXT NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
    
    -- Source information
    source_type TEXT NOT NULL DEFAULT 'manual', -- 'manual', 'csv', 'ai_generated'
    source_data JSONB DEFAULT '{}', -- Original CSV row data or AI data
    
    -- CSV specific fields
    csv_row_index INTEGER, -- Row number in original CSV
    csv_column_mapping JSONB, -- Column mapping used for this contact
    
    -- Contact creation metadata
    created_from_campaign BOOLEAN DEFAULT FALSE, -- Whether this contact was created as part of campaign
    original_lead_data JSONB DEFAULT '{}', -- Original lead data before contact creation
    
    -- Relationship metadata
    added_at TIMESTAMPTZ DEFAULT NOW(),
    added_by_user_id TEXT, -- User who added this contact to campaign
    
    -- Status
    status TEXT DEFAULT 'active' CHECK (status IN ('active', 'removed', 'bounced', 'unsubscribed')),
    
    -- Metadata
    metadata JSONB DEFAULT '{}',
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Ensure unique campaign-contact pairs
    UNIQUE(campaign_id, contact_id)
);

-- Create indexes
CREATE INDEX idx_campaign_contacts_campaign_id ON campaign_contacts(campaign_id);
CREATE INDEX idx_campaign_contacts_contact_id ON campaign_contacts(contact_id);
CREATE INDEX idx_campaign_contacts_organization_id ON campaign_contacts(organization_id);
CREATE INDEX idx_campaign_contacts_source_type ON campaign_contacts(source_type);
CREATE INDEX idx_campaign_contacts_status ON campaign_contacts(status);
CREATE INDEX idx_campaign_contacts_added_at ON campaign_contacts(added_at);

-- Create trigger for updated_at
CREATE TRIGGER update_campaign_contacts_updated_at BEFORE UPDATE ON campaign_contacts
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Enable Row Level Security
ALTER TABLE campaign_contacts ENABLE ROW LEVEL SECURITY;

-- Create RLS policies
CREATE POLICY "Users can view campaign contacts in their organization" ON campaign_contacts
    FOR SELECT USING (
        organization_id IN (
            SELECT organization_id FROM user_organizations 
            WHERE user_id = auth.uid()::text
        )
    );

CREATE POLICY "Users can manage campaign contacts in their organization" ON campaign_contacts
    FOR ALL USING (
        organization_id IN (
            SELECT organization_id FROM user_organizations 
            WHERE user_id = auth.uid()::text
        )
    );

-- Add comments for documentation
COMMENT ON TABLE campaign_contacts IS 'Tracks the relationship between campaigns and contacts, including CSV import details';
COMMENT ON COLUMN campaign_contacts.source_type IS 'How the contact was added: manual, csv, ai_generated';
COMMENT ON COLUMN campaign_contacts.source_data IS 'Original data used to create or add this contact';
COMMENT ON COLUMN campaign_contacts.csv_row_index IS 'Row number in original CSV file (0-based)';
COMMENT ON COLUMN campaign_contacts.csv_column_mapping IS 'Column mapping used when importing this contact from CSV';
COMMENT ON COLUMN campaign_contacts.created_from_campaign IS 'Whether this contact was created as part of this campaign';
COMMENT ON COLUMN campaign_contacts.original_lead_data IS 'Original lead data before being converted to contact'; 