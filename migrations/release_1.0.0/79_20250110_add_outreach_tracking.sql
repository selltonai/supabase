-- Migration: Add Outreach Tracking to Companies
-- Description: Add fields to track which companies have been used for outreach to avoid duplicate outreach
-- Author: System
-- Date: 2025-01-10

-- Add outreach tracking fields to companies table
ALTER TABLE companies ADD COLUMN IF NOT EXISTS used_for_outreach BOOLEAN DEFAULT FALSE;
ALTER TABLE companies ADD COLUMN IF NOT EXISTS first_outreach_date TIMESTAMPTZ;
ALTER TABLE companies ADD COLUMN IF NOT EXISTS last_outreach_date TIMESTAMPTZ;
ALTER TABLE companies ADD COLUMN IF NOT EXISTS outreach_count INTEGER DEFAULT 0;
ALTER TABLE companies ADD COLUMN IF NOT EXISTS outreach_campaigns TEXT[] DEFAULT '{}';

-- Create index for efficient filtering of companies not used for outreach
CREATE INDEX IF NOT EXISTS idx_companies_used_for_outreach ON companies(used_for_outreach);
CREATE INDEX IF NOT EXISTS idx_companies_first_outreach_date ON companies(first_outreach_date);
CREATE INDEX IF NOT EXISTS idx_companies_outreach_count ON companies(outreach_count);

-- Create function to mark companies as used for outreach
CREATE OR REPLACE FUNCTION mark_companies_for_outreach(
    p_organization_id TEXT,
    p_campaign_id UUID,
    p_campaign_name TEXT,
    p_company_identifiers JSONB -- Array of company identifiers (linkedin_url, name, domain)
)
RETURNS TABLE (
    company_id UUID,
    company_name TEXT,
    was_already_used BOOLEAN,
    marked_successfully BOOLEAN
) AS $$
DECLARE
    company_record RECORD;
    company_identifier JSONB;
    current_timestamp TIMESTAMPTZ := NOW();
BEGIN
    -- Loop through each company identifier
    FOR company_identifier IN SELECT * FROM jsonb_array_elements(p_company_identifiers)
    LOOP
        -- Try to find the company by LinkedIn URL first (most reliable)
        IF company_identifier->>'linkedin_url' IS NOT NULL AND company_identifier->>'linkedin_url' != '' THEN
            SELECT * INTO company_record
            FROM companies 
            WHERE organization_id = p_organization_id 
            AND linkedin_url = company_identifier->>'linkedin_url';
        END IF;
        
        -- If not found by LinkedIn URL, try by name
        IF NOT FOUND AND company_identifier->>'name' IS NOT NULL AND company_identifier->>'name' != '' THEN
            SELECT * INTO company_record
            FROM companies 
            WHERE organization_id = p_organization_id 
            AND LOWER(name) = LOWER(company_identifier->>'name');
        END IF;
        
        -- If not found by name, try by domain
        IF NOT FOUND AND company_identifier->>'domain' IS NOT NULL AND company_identifier->>'domain' != '' THEN
            SELECT * INTO company_record
            FROM companies 
            WHERE organization_id = p_organization_id 
            AND domain = company_identifier->>'domain';
        END IF;
        
        -- If company exists, update outreach tracking
        IF FOUND THEN
            UPDATE companies 
            SET 
                used_for_outreach = TRUE,
                first_outreach_date = COALESCE(first_outreach_date, current_timestamp),
                last_outreach_date = current_timestamp,
                outreach_count = outreach_count + 1,
                outreach_campaigns = CASE 
                    WHEN p_campaign_name = ANY(outreach_campaigns) THEN outreach_campaigns
                    ELSE array_append(outreach_campaigns, p_campaign_name)
                END,
                updated_at = current_timestamp
            WHERE id = company_record.id;
            
            RETURN QUERY SELECT 
                company_record.id,
                company_record.name,
                company_record.used_for_outreach AS was_already_used,
                TRUE AS marked_successfully;
        ELSE
            -- Company not found in database, create a new record
            INSERT INTO companies (
                organization_id,
                name,
                domain,
                linkedin_url,
                used_for_outreach,
                first_outreach_date,
                last_outreach_date,
                outreach_count,
                outreach_campaigns,
                created_at,
                updated_at
            ) VALUES (
                p_organization_id,
                COALESCE(company_identifier->>'name', 'Unknown Company'),
                company_identifier->>'domain',
                company_identifier->>'linkedin_url',
                TRUE,
                current_timestamp,
                current_timestamp,
                1,
                ARRAY[p_campaign_name],
                current_timestamp,
                current_timestamp
            ) RETURNING id, name INTO company_record;
            
            RETURN QUERY SELECT 
                company_record.id,
                company_record.name,
                FALSE AS was_already_used,
                TRUE AS marked_successfully;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Create function to get companies that haven't been used for outreach
CREATE OR REPLACE FUNCTION get_unused_companies_for_outreach(
    p_organization_id TEXT,
    p_limit INTEGER DEFAULT 100
)
RETURNS TABLE (
    id UUID,
    name TEXT,
    domain TEXT,
    linkedin_url TEXT,
    industry TEXT,
    city TEXT,
    country TEXT,
    created_at TIMESTAMPTZ
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        c.id,
        c.name,
        c.domain,
        c.linkedin_url,
        c.industry,
        c.city,
        c.country,
        c.created_at
    FROM companies c
    WHERE c.organization_id = p_organization_id
    AND (c.used_for_outreach = FALSE OR c.used_for_outreach IS NULL)
    ORDER BY c.created_at DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;

-- Create function to filter companies for campaign creation (exclude already used ones)
CREATE OR REPLACE FUNCTION filter_companies_for_campaign(
    p_organization_id TEXT,
    p_company_data JSONB -- Array of company data from CSV/AI
)
RETURNS TABLE (
    company_data JSONB,
    is_already_used BOOLEAN,
    existing_company_id UUID
) AS $$
DECLARE
    company_item JSONB;
    existing_company RECORD;
BEGIN
    -- Loop through each company in the input data
    FOR company_item IN SELECT * FROM jsonb_array_elements(p_company_data)
    LOOP
        -- Check if company already exists and has been used for outreach
        SELECT id, name, used_for_outreach INTO existing_company
        FROM companies 
        WHERE organization_id = p_organization_id 
        AND (
            (company_item->>'linkedin_url' IS NOT NULL AND linkedin_url = company_item->>'linkedin_url') OR
            (company_item->>'name' IS NOT NULL AND LOWER(name) = LOWER(company_item->>'name')) OR
            (company_item->>'domain' IS NOT NULL AND domain = company_item->>'domain')
        );
        
        IF FOUND THEN
            RETURN QUERY SELECT 
                company_item,
                COALESCE(existing_company.used_for_outreach, FALSE),
                existing_company.id;
        ELSE
            RETURN QUERY SELECT 
                company_item,
                FALSE,
                NULL::UUID;
        END IF;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Add comments for documentation
COMMENT ON COLUMN companies.used_for_outreach IS 'Whether this company has been used for any outreach campaigns';
COMMENT ON COLUMN companies.first_outreach_date IS 'Date when this company was first used for outreach';
COMMENT ON COLUMN companies.last_outreach_date IS 'Date when this company was last used for outreach';
COMMENT ON COLUMN companies.outreach_count IS 'Number of times this company has been used for outreach';
COMMENT ON COLUMN companies.outreach_campaigns IS 'Array of campaign names that have used this company';

COMMENT ON FUNCTION mark_companies_for_outreach IS 'Marks companies as used for outreach and tracks campaign usage';
COMMENT ON FUNCTION get_unused_companies_for_outreach IS 'Returns companies that have not been used for outreach';
COMMENT ON FUNCTION filter_companies_for_campaign IS 'Filters company data to identify which companies have already been used for outreach'; 