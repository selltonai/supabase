-- Simplified version of the pipeline analytics function that definitely returns all stages
DROP FUNCTION IF EXISTS get_sales_pipeline_analytics(TEXT);

CREATE OR REPLACE FUNCTION get_sales_pipeline_analytics(org_id TEXT)
RETURNS JSON AS $$
DECLARE
  pipeline_data JSON;
  industry_data JSON;
  location_data JSON;
  total_contacts INTEGER;
BEGIN
  -- Get total contacts for percentage calculation
  SELECT COUNT(*) INTO total_contacts
  FROM contacts
  WHERE organization_id = org_id;

  -- Get pipeline stage distribution - SIMPLIFIED VERSION
  SELECT json_agg(stage_data ORDER BY count DESC)
  INTO pipeline_data
  FROM (
    SELECT 
      json_build_object(
        'stage', CASE 
          WHEN pipeline_stage IS NULL OR pipeline_stage = '' THEN 'Unknown'
          ELSE UPPER(TRIM(pipeline_stage))
        END,
        'count', COUNT(*)::integer,
        'percentage', ROUND((COUNT(*)::numeric / NULLIF(total_contacts, 0) * 100), 2)
      ) as stage_data,
      COUNT(*) as count
    FROM contacts
    WHERE organization_id = org_id
    GROUP BY CASE 
      WHEN pipeline_stage IS NULL OR pipeline_stage = '' THEN 'Unknown'
      ELSE UPPER(TRIM(pipeline_stage))
    END
  ) grouped_stages;

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
      ct.location,
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
    ) ORDER BY ls.count DESC
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

-- Test the function
-- SELECT get_sales_pipeline_analytics('org_32BKjMNKEpb2wtrpswAogimVMkV');
