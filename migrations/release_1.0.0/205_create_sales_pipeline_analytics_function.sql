-- Create optimized function for Sales Pipeline Analytics
-- This function aggregates pipeline stage data and industry distribution

CREATE OR REPLACE FUNCTION get_sales_pipeline_analytics(org_id TEXT)
RETURNS JSON AS $$
DECLARE
  pipeline_data JSON;
  industry_data JSON;
  location_data JSON;
  result JSON;
BEGIN
  -- Get pipeline stage distribution
  WITH pipeline_stages AS (
    SELECT 
      CASE 
        WHEN ct.pipeline_stage IS NULL OR ct.pipeline_stage = '' THEN 'Unknown'
        ELSE UPPER(TRIM(ct.pipeline_stage))
      END as stage,
      COUNT(*) as count
    FROM contacts ct
    WHERE ct.organization_id = org_id
    GROUP BY CASE 
      WHEN ct.pipeline_stage IS NULL OR ct.pipeline_stage = '' THEN 'Unknown'
      ELSE UPPER(TRIM(ct.pipeline_stage))
    END
  ),
  pipeline_totals AS (
    SELECT SUM(count) as total FROM pipeline_stages
  )
  SELECT json_agg(
    json_build_object(
      'stage', ps.stage,
      'count', ps.count,
      'percentage', ROUND((ps.count::numeric / pt.total * 100), 2)
    ) ORDER BY ps.count DESC
  ) INTO pipeline_data
  FROM pipeline_stages ps
  CROSS JOIN pipeline_totals pt
  WHERE pt.total > 0;
  
  -- If no data, set empty array
  IF pipeline_data IS NULL THEN
    pipeline_data := '[]'::json;
  END IF;

  -- Get industry distribution (top 10)
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
  ),
  industry_totals AS (
    SELECT SUM(contact_count) as total FROM company_industries
  )
  SELECT json_agg(
    json_build_object(
      'industry', ci.industry,
      'count', ci.contact_count,
      'percentage', ROUND((ci.contact_count::numeric / NULLIF(it.total, 0) * 100), 2)
    ) ORDER BY ci.contact_count DESC
  ) INTO industry_data
  FROM company_industries ci, industry_totals it;

  -- Get location distribution (top 10)
  WITH location_stats AS (
    SELECT 
      COALESCE(ct.location, 'Unknown') as location,
      COUNT(*) as count
    FROM contacts ct
    JOIN company_contacts cc ON cc.contact_id = ct.id
    JOIN companies c ON cc.company_id = c.id
    WHERE c.organization_id = org_id
      AND ct.location IS NOT NULL
      AND ct.location != ''
    GROUP BY ct.location
    ORDER BY count DESC
    LIMIT 10
  ),
  location_totals AS (
    SELECT SUM(count) as total FROM location_stats
  )
  SELECT json_agg(
    json_build_object(
      'location', ls.location,
      'count', ls.count,
      'percentage', ROUND((ls.count::numeric / NULLIF(lt.total, 0) * 100), 2)
    )
  ) INTO location_data
  FROM location_stats ls, location_totals lt;

  -- Get summary statistics
  RETURN json_build_object(
    'pipeline', COALESCE(pipeline_data, '[]'::json),
    'industries', COALESCE(industry_data, '[]'::json),
    'locations', COALESCE(location_data, '[]'::json),
    'totalContacts', (
      SELECT COUNT(*) 
      FROM contacts
      WHERE organization_id = org_id
    ),
    'totalCompanies', (
      SELECT COUNT(*) 
      FROM companies 
      WHERE organization_id = org_id
    ),
    'averageContactsPerCompany', (
      SELECT ROUND(AVG(contact_count), 2)
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
        SELECT ROUND(
          COUNT(CASE WHEN UPPER(ct.pipeline_stage) = 'LEAD' THEN 1 END)::numeric / 
          NULLIF(COUNT(CASE WHEN UPPER(ct.pipeline_stage) = 'PROSPECT' THEN 1 END), 0) * 100, 2
        )
        FROM contacts ct
        WHERE ct.organization_id = org_id
      ),
      'leadToAppointment', (
        SELECT ROUND(
          COUNT(CASE WHEN UPPER(ct.pipeline_stage) IN ('APPOINTMENT_REQUESTED', 'APPOINTMENT_SCHEDULED') THEN 1 END)::numeric / 
          NULLIF(COUNT(CASE WHEN UPPER(ct.pipeline_stage) = 'LEAD' THEN 1 END), 0) * 100, 2
        )
        FROM contacts ct
        WHERE ct.organization_id = org_id
      ),
      'appointmentToPresentation', (
        SELECT ROUND(
          COUNT(CASE WHEN UPPER(ct.pipeline_stage) = 'PRESENTATION_SCHEDULED' THEN 1 END)::numeric / 
          NULLIF(COUNT(CASE WHEN UPPER(ct.pipeline_stage) IN ('APPOINTMENT_SCHEDULED') THEN 1 END), 0) * 100, 2
        )
        FROM contacts ct
        WHERE ct.organization_id = org_id
      )
    )
  );
END;
$$ LANGUAGE plpgsql STABLE;

-- Add indexes to optimize the function
CREATE INDEX IF NOT EXISTS idx_contacts_pipeline_stage ON contacts(pipeline_stage);
CREATE INDEX IF NOT EXISTS idx_contacts_location ON contacts(location);
CREATE INDEX IF NOT EXISTS idx_companies_industries ON companies USING GIN(industries);
CREATE INDEX IF NOT EXISTS idx_company_contacts_contact_id ON company_contacts(contact_id);
CREATE INDEX IF NOT EXISTS idx_company_contacts_company_id ON company_contacts(company_id);

COMMENT ON FUNCTION get_sales_pipeline_analytics(TEXT) IS 'Optimized function for Sales Pipeline Analytics dashboard component';
