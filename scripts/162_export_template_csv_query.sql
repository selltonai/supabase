-- SQL Query to Export Template CSV Format
-- This query generates a CSV file matching the template CSV format
-- Usage: 
--   psql -d your_database -c "\copy (SELECT ...) TO 'export.csv' CSV HEADER"
--   Or use COPY TO in a function
--   Or call the function: SELECT * FROM export_template_csv('org_id');
--   Or query the view: SELECT * FROM template_csv_export WHERE organization_id = 'your_org_id';
-- Note: Campaign filtering is not available if campaign_contacts table doesn't exist

-- ============================================================================
-- STEP 1: Diagnostic Queries - Run these first to check your data
-- ============================================================================

-- Check what organization IDs exist:
-- SELECT DISTINCT organization_id FROM contacts ORDER BY organization_id;

-- Check how many contacts exist per organization:
-- SELECT organization_id, COUNT(*) as contact_count 
-- FROM contacts 
-- GROUP BY organization_id 
-- ORDER BY contact_count DESC;

-- Check how many contacts have company relationships:
-- SELECT 
--     c.organization_id,
--     COUNT(*) as total_contacts,
--     COUNT(cc.id) as contacts_with_companies,
--     COUNT(*) - COUNT(cc.id) as contacts_without_companies
-- FROM contacts c
-- LEFT JOIN company_contacts cc ON cc.contact_id = c.id AND cc.organization_id = c.organization_id
-- GROUP BY c.organization_id;

-- ============================================================================
-- STEP 2: Create a VIEW for easy querying
-- ============================================================================

-- Drop view if it exists
DROP VIEW IF EXISTS template_csv_export CASCADE;

-- Create view that shows all contacts (with or without companies)
-- Uses DISTINCT ON to ensure one row per contact (prevents duplicates from multiple company relationships)
CREATE VIEW template_csv_export AS
SELECT DISTINCT ON (c.id)
    -- First Name
    COALESCE(c.firstname, SPLIT_PART(c.name, ' ', 1), '') AS "First Name",
    
    -- Last Name  
    COALESCE(c.lastname, 
        CASE 
            WHEN array_length(string_to_array(c.name, ' '), 1) > 1 
                THEN array_to_string((string_to_array(c.name, ' '))[2:], ' ')
            ELSE ''
        END, '') AS "Last Name",
    
    -- Title (Job Title)
    COALESCE(c.headline, '') AS "Title",
    
    -- Company Name
    COALESCE(comp.name, '') AS "Company Name",
    
    -- Company website
    COALESCE(comp.website, '') AS "Company website",
    
    -- Personal LinkedIn
    COALESCE(c.linkedin_url, '') AS "Personal LinkedIn",
    
    -- Company LinkedIn
    COALESCE(comp.linkedin_url, '') AS "Company LinkedIn",
    
    -- Company email address (leave empty - we don't store generic company emails)
    '' AS "Company email address",
    
    -- Personal Email address
    COALESCE(c.email, '') AS "Personal Email address",
    
    -- Mobile Number
    COALESCE(c.phone, '') AS "Mobile Number",
    
    -- Company Number
    COALESCE(comp.phone, '') AS "Company Number",
    
    -- Person location (single location name - prioritize city, then default, then country)
    COALESCE(
        CASE 
            WHEN c.location IS NOT NULL THEN
                CASE 
                    WHEN c.location->>'city' IS NOT NULL THEN c.location->>'city'
                    WHEN c.location->>'default' IS NOT NULL THEN c.location->>'default'
                    WHEN c.location->>'country' IS NOT NULL THEN c.location->>'country'
                    ELSE ''
                END
            ELSE ''
        END,
        ''
    ) AS "Person location",
    
    -- Company location
    COALESCE(comp.location, '') AS "Company location",
    
    -- Stage (Pipeline Stage) - default to PROSPECT if null
    COALESCE(c.pipeline_stage, 'PROSPECT') AS "Stage",
    
    -- Technologies used (from contacts skills or company specialities)
    COALESCE(
        CASE 
            WHEN c.skills IS NOT NULL AND jsonb_typeof(c.skills) = 'array' THEN
                ARRAY_TO_STRING(
                    ARRAY(SELECT jsonb_array_elements_text(c.skills)),
                    ', '
                )
            WHEN comp.specialities IS NOT NULL AND array_length(comp.specialities, 1) > 0 THEN
                ARRAY_TO_STRING(comp.specialities, ', ')
            ELSE ''
        END,
        ''
    ) AS "Technologies used"

FROM contacts c
-- Join with company_contacts to get company relationship (LEFT JOIN to include contacts without companies)
LEFT JOIN company_contacts cc ON cc.contact_id = c.id AND cc.organization_id = c.organization_id
-- Join with companies to get company data
LEFT JOIN companies comp ON comp.id = cc.company_id AND comp.organization_id = c.organization_id
-- Order by contact ID and prioritize company relationships with more complete data
ORDER BY c.id, 
    CASE WHEN comp.id IS NOT NULL THEN 0 ELSE 1 END,  -- Prefer contacts with companies
    CASE WHEN comp.name IS NOT NULL AND comp.name != '' THEN 0 ELSE 1 END,  -- Prefer companies with names
    cc.created_at DESC NULLS LAST;  -- Prefer most recent company relationship

-- Grant access to the view
COMMENT ON VIEW template_csv_export IS 'View for exporting contacts in template CSV format. Query with: SELECT * FROM template_csv_export ORDER BY "Company Name", "First Name" LIMIT 1000;';

-- ============================================================================
-- OPTION 1: Query the VIEW (Easiest - Recommended)
-- ============================================================================
-- This shows ALL contacts (with or without companies) - NO FILTERING

-- SELECT * FROM template_csv_export ORDER BY "Company Name", "First Name", "Last Name" LIMIT 1000;

-- To show only contacts WITH companies:
-- SELECT * FROM template_csv_export 
-- WHERE "Company Name" != '' 
-- ORDER BY "Company Name", "First Name", "Last Name" LIMIT 1000;

-- ============================================================================
-- OPTION 2: Simple Direct Query - Shows ALL data (NO FILTERING)
-- ============================================================================
-- Just run this query - it shows all contacts from all organizations
-- Uses DISTINCT ON to ensure one row per contact (prevents duplicates from multiple company relationships)

SELECT DISTINCT ON (c.id)
    -- First Name
    COALESCE(c.firstname, SPLIT_PART(c.name, ' ', 1), '') AS "First Name",
    
    -- Last Name  
    COALESCE(c.lastname, 
        CASE 
            WHEN array_length(string_to_array(c.name, ' '), 1) > 1 
                THEN array_to_string((string_to_array(c.name, ' '))[2:], ' ')
            ELSE ''
        END, '') AS "Last Name",
    
    -- Title (Job Title)
    COALESCE(c.headline, '') AS "Title",
    
    -- Company Name
    COALESCE(comp.name, '') AS "Company Name",
    
    -- Company website
    COALESCE(comp.website, '') AS "Company website",
    
    -- Personal LinkedIn
    COALESCE(c.linkedin_url, '') AS "Personal LinkedIn",
    
    -- Company LinkedIn
    COALESCE(comp.linkedin_url, '') AS "Company LinkedIn",
    
    -- Company email address
    'wouter@konav.ai' AS "Company email address",
    
    -- Personal Email address
    'wouter@konav.ai' AS "Personal Email address",
    
    -- Mobile Number
    COALESCE(c.phone, '') AS "Mobile Number",
    
    -- Company Number
    COALESCE(comp.phone, '') AS "Company Number",
    
    -- Person location (single location name - prioritize city, then default, then country)
    COALESCE(
        CASE 
            WHEN c.location IS NOT NULL THEN
                CASE 
                    WHEN c.location->>'city' IS NOT NULL THEN c.location->>'city'
                    WHEN c.location->>'default' IS NOT NULL THEN c.location->>'default'
                    WHEN c.location->>'country' IS NOT NULL THEN c.location->>'country'
                    ELSE ''
                END
            ELSE ''
        END,
        ''
    ) AS "Person location",
    
    -- Company location
    COALESCE(comp.location, '') AS "Company location",
    
    -- Stage (Pipeline Stage) - default to PROSPECT if null
    COALESCE(c.pipeline_stage, 'PROSPECT') AS "Stage",
    
    -- Technologies used (from contacts skills or company specialities)
    COALESCE(
        CASE 
            WHEN c.skills IS NOT NULL AND jsonb_typeof(c.skills) = 'array' THEN
                ARRAY_TO_STRING(
                    ARRAY(SELECT jsonb_array_elements_text(c.skills)),
                    ', '
                )
            WHEN comp.specialities IS NOT NULL AND array_length(comp.specialities, 1) > 0 THEN
                ARRAY_TO_STRING(comp.specialities, ', ')
            ELSE ''
        END,
        ''
    ) AS "Technologies used"

FROM contacts c
-- Join with company_contacts to get company relationship (LEFT JOIN to include contacts without companies)
LEFT JOIN company_contacts cc ON cc.contact_id = c.id AND cc.organization_id = c.organization_id
-- Join with companies to get company data
LEFT JOIN companies comp ON comp.id = cc.company_id AND comp.organization_id = c.organization_id
-- Order by contact ID and prioritize company relationships with more complete data
ORDER BY c.id, 
    CASE WHEN comp.id IS NOT NULL THEN 0 ELSE 1 END,  -- Prefer contacts with companies
    CASE WHEN comp.name IS NOT NULL AND comp.name != '' THEN 0 ELSE 1 END,  -- Prefer companies with names
    cc.created_at DESC NULLS LAST,  -- Prefer most recent company relationship
    comp.name NULLS LAST, c.name
LIMIT 100;

-- ============================================================================
-- OPTION 2: Function-based Query (More reusable)
-- ============================================================================

-- Create a function to export template CSV format
-- Note: Campaign filtering is not available if campaign_contacts table doesn't exist
CREATE OR REPLACE FUNCTION export_template_csv(
    p_organization_id TEXT
)
RETURNS TABLE (
    "First Name" TEXT,
    "Last Name" TEXT,
    "Title" TEXT,
    "Company Name" TEXT,
    "Company website" TEXT,
    "Personal LinkedIn" TEXT,
    "Company LinkedIn" TEXT,
    "Company email address" TEXT,
    "Personal Email address" TEXT,
    "Mobile Number" TEXT,
    "Company Number" TEXT,
    "Person location" TEXT,
    "Company location" TEXT,
    "Stage" TEXT,
    "Technologies used" TEXT
) AS $$
BEGIN
    RETURN QUERY
    SELECT DISTINCT ON (c.id)
    -- First Name
    COALESCE(c.firstname, SPLIT_PART(c.name, ' ', 1), '') AS "First Name",
    
    -- Last Name  
    COALESCE(c.lastname, 
        CASE 
            WHEN array_length(string_to_array(c.name, ' '), 1) > 1 
                THEN array_to_string((string_to_array(c.name, ' '))[2:], ' ')
            ELSE ''
        END, '') AS "Last Name",
    
    -- Title (Job Title)
    COALESCE(c.headline, '') AS "Title",
    
    -- Company Name
    COALESCE(comp.name, '') AS "Company Name",
    
    -- Company website
    COALESCE(comp.website, '') AS "Company website",
    
    -- Personal LinkedIn
    COALESCE(c.linkedin_url, '') AS "Personal LinkedIn",
    
    -- Company LinkedIn
    COALESCE(comp.linkedin_url, '') AS "Company LinkedIn",
    
    -- Company email address (leave empty - we don't store generic company emails)
    '' AS "Company email address",
    
    -- Personal Email address
    COALESCE(c.email, '') AS "Personal Email address",
    
    -- Mobile Number
    COALESCE(c.phone, '') AS "Mobile Number",
    
    -- Company Number
    COALESCE(comp.phone, '') AS "Company Number",
    
    -- Person location (single location name - prioritize city, then default, then country)
    COALESCE(
        CASE 
            WHEN c.location IS NOT NULL THEN
                CASE 
                    WHEN c.location->>'city' IS NOT NULL THEN c.location->>'city'
                    WHEN c.location->>'default' IS NOT NULL THEN c.location->>'default'
                    WHEN c.location->>'country' IS NOT NULL THEN c.location->>'country'
                    ELSE ''
                END
            ELSE ''
        END,
        ''
    ) AS "Person location",
    
    -- Company location
    COALESCE(comp.location, '') AS "Company location",
    
    -- Stage (Pipeline Stage) - default to PROSPECT if null
    COALESCE(c.pipeline_stage, 'PROSPECT') AS "Stage",
    
    -- Technologies used (from contacts skills or company specialities)
    COALESCE(
        CASE 
            WHEN c.skills IS NOT NULL AND jsonb_typeof(c.skills) = 'array' THEN
                ARRAY_TO_STRING(
                    ARRAY(SELECT jsonb_array_elements_text(c.skills)),
                    ', '
                )
            WHEN comp.specialities IS NOT NULL AND array_length(comp.specialities, 1) > 0 THEN
                ARRAY_TO_STRING(comp.specialities, ', ')
            ELSE ''
        END,
        ''
    ) AS "Technologies used"

FROM contacts c
-- Join with company_contacts to get company relationship
    LEFT JOIN company_contacts cc ON cc.contact_id = c.id AND cc.organization_id = c.organization_id
-- Join with companies to get company data
    LEFT JOIN companies comp ON comp.id = cc.company_id AND comp.organization_id = c.organization_id

WHERE 
        -- Filter by organization
        c.organization_id = p_organization_id
        
        -- Uncomment the line below to only show contacts WITH companies:
        -- AND comp.id IS NOT NULL
        
    -- Order by contact ID and prioritize company relationships with more complete data
    ORDER BY c.id, 
        CASE WHEN comp.id IS NOT NULL THEN 0 ELSE 1 END,  -- Prefer contacts with companies
        CASE WHEN comp.name IS NOT NULL AND comp.name != '' THEN 0 ELSE 1 END,  -- Prefer companies with names
        cc.created_at DESC NULLS LAST,  -- Prefer most recent company relationship
        comp.name NULLS LAST, c.name;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- USAGE EXAMPLES
-- ============================================================================

-- Example 1: Query the VIEW (EASIEST - Shows ALL data in table format):
-- SELECT * FROM template_csv_export ORDER BY "Company Name", "First Name" LIMIT 1000;

-- Example 2: Query VIEW with only contacts that have companies:
-- SELECT * FROM template_csv_export 
-- WHERE "Company Name" != '' 
-- ORDER BY "Company Name", "First Name" LIMIT 1000;

-- Example 3: Use the simple direct query (OPTION 2 above) - just copy and run it!

-- Example 4: Export to CSV file using psql (using VIEW):
-- \copy (SELECT * FROM template_csv_export LIMIT 10000) TO 'export.csv' WITH CSV HEADER;

-- Example 5: Export using COPY TO (requires superuser, using VIEW):
-- COPY (SELECT * FROM template_csv_export LIMIT 10000) TO '/tmp/export.csv' WITH CSV HEADER;

