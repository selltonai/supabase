-- Migration: Update ICP Settings Structure
-- Description: Adds industries and preferred_job_titles fields, splits ideal_clients into ideal_customers and ideal_persons
-- Author: System
-- Date: 2025-02-01

-- Function to migrate existing ideal_clients to ideal_customers and ideal_persons
CREATE OR REPLACE FUNCTION migrate_ideal_clients_to_split_fields() RETURNS void AS $$
DECLARE
    org_record RECORD;
    ideal_customers jsonb;
    ideal_persons jsonb;
    client_url text;
    updated_icp jsonb;
BEGIN
    -- Loop through all organizations with ICP settings
    FOR org_record IN 
        SELECT id, icp_settings 
        FROM organization_settings 
        WHERE icp_settings IS NOT NULL 
        AND icp_settings->>'ideal_clients' IS NOT NULL
    LOOP
        ideal_customers := '[]'::jsonb;
        ideal_persons := '[]'::jsonb;
        
        -- Split ideal_clients based on URL type
        FOR client_url IN 
            SELECT jsonb_array_elements_text(org_record.icp_settings->'ideal_clients')
        LOOP
            IF client_url LIKE '%/company/%' THEN
                ideal_customers := ideal_customers || to_jsonb(client_url);
            ELSIF client_url LIKE '%/in/%' THEN
                ideal_persons := ideal_persons || to_jsonb(client_url);
            END IF;
        END LOOP;
        
        -- Build updated ICP settings
        updated_icp := org_record.icp_settings;
        
        -- Add new fields
        updated_icp := jsonb_set(updated_icp, '{ideal_customers}', ideal_customers);
        updated_icp := jsonb_set(updated_icp, '{ideal_persons}', ideal_persons);
        
        -- Add empty arrays for new fields if they don't exist
        IF NOT (updated_icp ? 'industries') THEN
            updated_icp := jsonb_set(updated_icp, '{industries}', '[]'::jsonb);
        END IF;
        
        IF NOT (updated_icp ? 'preferred_job_titles') THEN
            updated_icp := jsonb_set(updated_icp, '{preferred_job_titles}', '[]'::jsonb);
        END IF;
        
        -- Update the organization settings
        UPDATE organization_settings 
        SET icp_settings = updated_icp
        WHERE id = org_record.id;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Function to ensure current_customers only contains company URLs
CREATE OR REPLACE FUNCTION clean_current_customers() RETURNS void AS $$
DECLARE
    org_record RECORD;
    cleaned_customers jsonb;
    customer_url text;
BEGIN
    -- Loop through all organizations with current_customers
    FOR org_record IN 
        SELECT id, icp_settings 
        FROM organization_settings 
        WHERE icp_settings IS NOT NULL 
        AND icp_settings->>'current_customers' IS NOT NULL
    LOOP
        cleaned_customers := '[]'::jsonb;
        
        -- Keep only company URLs in current_customers
        FOR customer_url IN 
            SELECT jsonb_array_elements_text(org_record.icp_settings->'current_customers')
        LOOP
            IF customer_url LIKE '%/company/%' THEN
                cleaned_customers := cleaned_customers || to_jsonb(customer_url);
            END IF;
        END LOOP;
        
        -- Update the current_customers field
        UPDATE organization_settings 
        SET icp_settings = jsonb_set(icp_settings, '{current_customers}', cleaned_customers)
        WHERE id = org_record.id;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Run the migration
SELECT migrate_ideal_clients_to_split_fields();
SELECT clean_current_customers();

-- Drop the migration functions
DROP FUNCTION IF EXISTS migrate_ideal_clients_to_split_fields();
DROP FUNCTION IF EXISTS clean_current_customers();

-- Update default ICP settings for new organizations
ALTER TABLE organization_settings 
ALTER COLUMN icp_settings SET DEFAULT '{
    "ideal_customers": [],
    "ideal_persons": [],
    "current_customers": [],
    "exclusion_list": [],
    "industries": [],
    "preferred_job_titles": []
}'::jsonb;

-- Add comment about the new structure
COMMENT ON COLUMN organization_settings.icp_settings IS 'ICP settings including ideal customers (companies), ideal persons (individuals), current customers (companies only), exclusion list, industries, and preferred job titles';