-- Combined Migration: Create Campaign Contacts Table and Fix Relationships
-- This script combines migrations 51, 69, 70, 71, and 72
-- Run this on production database to fix the campaign_contacts relationship

BEGIN;

-- 1. Create campaign_contacts table to track campaign-contact relationships
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

-- 2. Create indexes
CREATE INDEX IF NOT EXISTS idx_campaign_contacts_campaign_id ON campaign_contacts(campaign_id);
CREATE INDEX IF NOT EXISTS idx_campaign_contacts_contact_id ON campaign_contacts(contact_id);
CREATE INDEX IF NOT EXISTS idx_campaign_contacts_organization_id ON campaign_contacts(organization_id);
CREATE INDEX IF NOT EXISTS idx_campaign_contacts_source_type ON campaign_contacts(source_type);
CREATE INDEX IF NOT EXISTS idx_campaign_contacts_status ON campaign_contacts(status);
CREATE INDEX IF NOT EXISTS idx_campaign_contacts_added_at ON campaign_contacts(added_at);
CREATE INDEX IF NOT EXISTS idx_campaign_contacts_contact_campaigns ON campaign_contacts(contact_id, added_at DESC);
CREATE INDEX IF NOT EXISTS idx_campaign_contacts_campaign_contacts ON campaign_contacts(campaign_id, added_at DESC);

-- 3. Create trigger for updated_at (only if the function exists)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'update_updated_at_column') THEN
        DROP TRIGGER IF EXISTS update_campaign_contacts_updated_at ON campaign_contacts;
        CREATE TRIGGER update_campaign_contacts_updated_at BEFORE UPDATE ON campaign_contacts
            FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
    END IF;
END $$;

-- 4. Enable Row Level Security
ALTER TABLE campaign_contacts ENABLE ROW LEVEL SECURITY;

-- 5. Create RLS policies
DROP POLICY IF EXISTS "Users can view campaign contacts in their organization" ON campaign_contacts;
CREATE POLICY "Users can view campaign contacts in their organization" ON campaign_contacts
    FOR SELECT USING (
        organization_id IN (
            SELECT organization_id FROM user_organizations 
            WHERE user_id = auth.uid()::text
        )
    );

DROP POLICY IF EXISTS "Users can manage campaign contacts in their organization" ON campaign_contacts;
CREATE POLICY "Users can manage campaign contacts in their organization" ON campaign_contacts
    FOR ALL USING (
        organization_id IN (
            SELECT organization_id FROM user_organizations 
            WHERE user_id = auth.uid()::text
        )
    );

-- 6. Migrate existing campaign_id data from contacts table (if the column exists)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'contacts' AND column_name = 'campaign_id') THEN
        INSERT INTO campaign_contacts (
            campaign_id,
            contact_id,
            organization_id,
            source_type,
            created_from_campaign,
            added_by_user_id,
            added_at,
            status
        )
        SELECT 
            c.campaign_id,
            c.id as contact_id,
            c.organization_id,
            'manual' as source_type,
            false as created_from_campaign,
            c.user_id as added_by_user_id,
            c.created_at as added_at,
            'active' as status
        FROM contacts c
        WHERE c.campaign_id IS NOT NULL
        ON CONFLICT (campaign_id, contact_id) DO NOTHING;
    END IF;
END $$;

-- 7. Migrate existing campaign_emails to campaign_contacts (if not already there)
INSERT INTO campaign_contacts (
    campaign_id,
    contact_id,
    organization_id,
    source_type,
    created_from_campaign,
    added_at,
    status
)
SELECT DISTINCT
    ce.campaign_id,
    ce.contact_id,
    ce.organization_id,
    'manual' as source_type,
    false as created_from_campaign,
    ce.created_at as added_at,
    'active' as status
FROM campaign_emails ce
WHERE NOT EXISTS (
    SELECT 1 FROM campaign_contacts cc 
    WHERE cc.campaign_id = ce.campaign_id 
    AND cc.contact_id = ce.contact_id
);

-- 8. Remove deprecated columns if they exist
ALTER TABLE contacts DROP COLUMN IF EXISTS campaign_id;
ALTER TABLE contacts DROP COLUMN IF EXISTS campaign;
ALTER TABLE campaigns DROP COLUMN IF EXISTS selected_contacts;

-- 9. Update campaign total_contacts count based on campaign_contacts
UPDATE campaigns 
SET total_contacts = (
    SELECT COUNT(*)
    FROM campaign_contacts cc
    WHERE cc.campaign_id = campaigns.id
        AND cc.status = 'active'
);

-- 10. Create function to automatically update campaign metrics when contacts are added/removed
CREATE OR REPLACE FUNCTION update_campaign_contact_count()
RETURNS TRIGGER AS $func$
BEGIN
    -- Update the campaign's total_contacts
    IF TG_OP = 'INSERT' THEN
        -- Adding a contact
        UPDATE campaigns 
        SET 
            total_contacts = (
                SELECT COUNT(*)
                FROM campaign_contacts cc
                WHERE cc.campaign_id = NEW.campaign_id
                    AND cc.status = 'active'
            )
        WHERE id = NEW.campaign_id;
        
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        -- Status change or other update
        UPDATE campaigns 
        SET 
            total_contacts = (
                SELECT COUNT(*)
                FROM campaign_contacts cc
                WHERE cc.campaign_id = NEW.campaign_id
                    AND cc.status = 'active'
            )
        WHERE id = NEW.campaign_id;
        
        -- If campaign_id changed, update both old and new campaigns
        IF OLD.campaign_id != NEW.campaign_id THEN
            UPDATE campaigns 
            SET 
                total_contacts = (
                    SELECT COUNT(*)
                    FROM campaign_contacts cc
                    WHERE cc.campaign_id = OLD.campaign_id
                        AND cc.status = 'active'
                )
            WHERE id = OLD.campaign_id;
        END IF;
        
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        -- Removing a contact
        UPDATE campaigns 
        SET 
            total_contacts = (
                SELECT COUNT(*)
                FROM campaign_contacts cc
                WHERE cc.campaign_id = OLD.campaign_id
                    AND cc.status = 'active'
            )
        WHERE id = OLD.campaign_id;
        
        RETURN OLD;
    END IF;
    
    RETURN NULL;
END;
$func$ LANGUAGE plpgsql;

-- 11. Create trigger to automatically update campaign contact counts
DROP TRIGGER IF EXISTS trigger_update_campaign_contact_count ON campaign_contacts;
CREATE TRIGGER trigger_update_campaign_contact_count
    AFTER INSERT OR UPDATE OR DELETE ON campaign_contacts
    FOR EACH ROW
    EXECUTE FUNCTION update_campaign_contact_count();

-- 12. Create helper functions for querying campaign-contact relationships
CREATE OR REPLACE FUNCTION get_contact_campaigns(p_contact_id UUID)
RETURNS TABLE (
    campaign_id UUID,
    campaign_name TEXT,
    campaign_status TEXT,
    campaign_type TEXT,
    added_at TIMESTAMPTZ,
    source_type TEXT,
    relationship_status TEXT
) AS $func$
BEGIN
    RETURN QUERY
    SELECT 
        c.id as campaign_id,
        c.name as campaign_name,
        c.status::TEXT as campaign_status,
        c.campaign_type,
        cc.added_at,
        cc.source_type,
        cc.status as relationship_status
    FROM campaign_contacts cc
    JOIN campaigns c ON c.id = cc.campaign_id
    WHERE cc.contact_id = p_contact_id
    ORDER BY cc.added_at DESC;
END;
$func$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_campaign_contacts(p_campaign_id UUID)
RETURNS TABLE (
    contact_id UUID,
    contact_name TEXT,
    contact_email TEXT,
    company_name TEXT,
    job_title TEXT,
    added_at TIMESTAMPTZ,
    source_type TEXT,
    relationship_status TEXT,
    created_from_campaign BOOLEAN
) AS $func$
BEGIN
    RETURN QUERY
    SELECT 
        c.id as contact_id,
        c.name as contact_name,
        c.email as contact_email,
        c.company_name,
        c.job_title,
        cc.added_at,
        cc.source_type,
        cc.status as relationship_status,
        cc.created_from_campaign
    FROM campaign_contacts cc
    JOIN contacts c ON c.id = cc.contact_id
    WHERE cc.campaign_id = p_campaign_id
    ORDER BY cc.added_at DESC;
END;
$func$ LANGUAGE plpgsql;

-- 13. Add comments for documentation
COMMENT ON TABLE campaign_contacts IS 'Tracks the relationship between campaigns and contacts, including CSV import details';
COMMENT ON COLUMN campaign_contacts.source_type IS 'How the contact was added: manual, csv, ai_generated';
COMMENT ON COLUMN campaign_contacts.source_data IS 'Original data used to create or add this contact';
COMMENT ON COLUMN campaign_contacts.csv_row_index IS 'Row number in original CSV file (0-based)';
COMMENT ON COLUMN campaign_contacts.csv_column_mapping IS 'Column mapping used when importing this contact from CSV';
COMMENT ON COLUMN campaign_contacts.created_from_campaign IS 'Whether this contact was created as part of this campaign';
COMMENT ON COLUMN campaign_contacts.original_lead_data IS 'Original lead data before being converted to contact';
COMMENT ON FUNCTION update_campaign_contact_count() IS 'Automatically updates campaign total_contacts when campaign_contacts changes';
COMMENT ON FUNCTION get_contact_campaigns(UUID) IS 'Returns all campaigns that a contact is part of';
COMMENT ON FUNCTION get_campaign_contacts(UUID) IS 'Returns all contacts in a specific campaign with relationship details';

COMMIT; 