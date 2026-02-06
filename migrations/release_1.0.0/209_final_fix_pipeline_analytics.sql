-- FINAL FIX: Complete rewrite of pipeline analytics function
DROP FUNCTION IF EXISTS get_sales_pipeline_analytics(TEXT);

CREATE OR REPLACE FUNCTION get_sales_pipeline_analytics(org_id TEXT)
RETURNS JSON AS $$
DECLARE
  pipeline_data JSON;
  industry_data JSON;
  location_data JSON;
  total_contacts INTEGER;
BEGIN
  -- Get total contacts
  SELECT COUNT(*) INTO total_contacts
  FROM contacts
  WHERE organization_id = org_id;

  -- Get pipeline stages (WORKING VERSION)
  SELECT json_agg(stage_row ORDER BY count DESC)
  INTO pipeline_data
  FROM (
    SELECT 
      json_build_object(
        'stage', UPPER(COALESCE(NULLIF(TRIM(pipeline_stage), ''), 'Unknown')),
        'count', COUNT(*)::integer,
        'percentage', CASE 
          WHEN total_contacts > 0 THEN ROUND((COUNT(*)::numeric / total_contacts * 100), 2)
          ELSE 0
        END
      ) as stage_row,
      COUNT(*) as count
    FROM contacts
    WHERE organization_id = org_id
    GROUP BY UPPER(COALESCE(NULLIF(TRIM(pipeline_stage), ''), 'Unknown'))
  ) stages;

  -- Get industry distribution (safe version)
  BEGIN
    WITH company_industries AS (
      SELECT 
        UNNEST(COALESCE(c.industries, ARRAY[]::text[])) as industry,
        COUNT(DISTINCT cc.id) as contact_count
      FROM companies c
      JOIN company_contacts cc ON cc.company_id = c.id
      WHERE c.organization_id = org_id
      GROUP BY industry
      ORDER BY contact_count DESC
      LIMIT 10
    )
    SELECT json_agg(
      json_build_object(
        'industry', ci.industry,
        'count', ci.contact_count,
        'percentage', CASE 
          WHEN (SELECT SUM(contact_count) FROM company_industries) > 0 
          THEN ROUND((ci.contact_count::numeric / (SELECT SUM(contact_count) FROM company_industries) * 100), 2)
          ELSE 0
        END
      ) ORDER BY ci.contact_count DESC
    ) INTO industry_data
    FROM company_industries ci;
  EXCEPTION WHEN OTHERS THEN
    industry_data := '[]'::json;
  END;

  -- Get location distribution (safe version)
  BEGIN
    WITH location_stats AS (
      SELECT 
        ct.location,
        COUNT(*) as count
      FROM contacts ct
      WHERE ct.organization_id = org_id
        AND ct.location IS NOT NULL
        AND ct.location != ''
      GROUP BY ct.location
      ORDER BY count DESC
      LIMIT 10
    )
    SELECT json_agg(
      json_build_object(
        'location', ls.location,
        'count', ls.count,
        'percentage', CASE 
          WHEN (SELECT SUM(count) FROM location_stats) > 0
          THEN ROUND((ls.count::numeric / (SELECT SUM(count) FROM location_stats) * 100), 2)
          ELSE 0
        END
      ) ORDER BY ls.count DESC
    ) INTO location_data
    FROM location_stats ls;
  EXCEPTION WHEN OTHERS THEN
    location_data := '[]'::json;
  END;

  -- Return complete result
  RETURN json_build_object(
    'pipeline', COALESCE(pipeline_data, '[]'::json),
    'industries', COALESCE(industry_data, '[]'::json),
    'locations', COALESCE(location_data, '[]'::json),
    'totalContacts', total_contacts,
    'totalCompanies', (
      SELECT COUNT(*) FROM companies WHERE organization_id = org_id
    ),
    'averageContactsPerCompany', (
      SELECT COALESCE(ROUND(AVG(contact_count), 2), 0)
      FROM (
        SELECT COUNT(cc.id) as contact_count
        FROM companies c
        LEFT JOIN company_contacts cc ON cc.company_id = c.id
        WHERE c.organization_id = org_id
        GROUP BY c.id
      ) counts
    ),
    'companiesWithContacts', (
      SELECT COUNT(DISTINCT c.id)
      FROM companies c
      JOIN company_contacts cc ON cc.company_id = c.id
      WHERE c.organization_id = org_id
    ),
    'stageConversionRates', json_build_object(
      'prospectToLead', (
        SELECT COALESCE(ROUND(
          COUNT(CASE WHEN UPPER(pipeline_stage) = 'LEAD' THEN 1 END)::numeric / 
          NULLIF(COUNT(CASE WHEN UPPER(pipeline_stage) = 'PROSPECT' THEN 1 END), 0) * 100, 2
        ), 0)
        FROM contacts
        WHERE organization_id = org_id
      ),
      'leadToAppointment', (
        SELECT COALESCE(ROUND(
          COUNT(CASE WHEN UPPER(pipeline_stage) IN ('APPOINTMENT_REQUESTED', 'APPOINTMENT_SCHEDULED') THEN 1 END)::numeric / 
          NULLIF(COUNT(CASE WHEN UPPER(pipeline_stage) = 'LEAD' THEN 1 END), 0) * 100, 2
        ), 0)
        FROM contacts
        WHERE organization_id = org_id
      ),
      'appointmentToPresentation', (
        SELECT COALESCE(ROUND(
          COUNT(CASE WHEN UPPER(pipeline_stage) = 'PRESENTATION_SCHEDULED' THEN 1 END)::numeric / 
          NULLIF(COUNT(CASE WHEN UPPER(pipeline_stage) IN ('APPOINTMENT_SCHEDULED') THEN 1 END), 0) * 100, 2
        ), 0)
        FROM contacts
        WHERE organization_id = org_id
      )
    )
  );
END;
$$ LANGUAGE plpgsql STABLE;

-- Add indexes if they don't exist
CREATE INDEX IF NOT EXISTS idx_contacts_pipeline_stage ON contacts(pipeline_stage);
CREATE INDEX IF NOT EXISTS idx_contacts_organization_id ON contacts(organization_id);
CREATE INDEX IF NOT EXISTS idx_contacts_location ON contacts(location);
CREATE INDEX IF NOT EXISTS idx_companies_industries ON companies USING GIN(industries);
CREATE INDEX IF NOT EXISTS idx_company_contacts_contact_id ON company_contacts(contact_id);
CREATE INDEX IF NOT EXISTS idx_company_contacts_company_id ON company_contacts(company_id);

COMMENT ON FUNCTION get_sales_pipeline_analytics(TEXT) IS 'Fixed version that properly returns all pipeline stages';

-- Test it:
-- SELECT get_sales_pipeline_analytics('org_32BKjMNKEpb2wtrpswAogimVMkV');


