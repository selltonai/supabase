-- FIX: Pipeline conversion rates calculation
-- Problem: Current calculation divides contacts AT each stage, not contacts that PASSED THROUGH each stage
-- Example bug: 1 Lead + 2 Appointments = 2/1 = 200% conversion (impossible!)
-- Solution: Calculate cumulative progression through the funnel

DROP FUNCTION IF EXISTS get_sales_pipeline_analytics(TEXT);

CREATE OR REPLACE FUNCTION get_sales_pipeline_analytics(org_id TEXT)
RETURNS JSON AS $$
DECLARE
  pipeline_data JSON;
  industry_data JSON;
  location_data JSON;
  total_contacts INTEGER;
  -- Counts for conversion rate calculation (cumulative, meaning at stage OR beyond)
  count_at_or_beyond_lead INTEGER;
  count_at_or_beyond_appointment INTEGER;
  count_at_or_beyond_appointment_scheduled INTEGER;
  count_at_or_beyond_presentation INTEGER;
BEGIN
  -- Get total contacts
  SELECT COUNT(*) INTO total_contacts
  FROM contacts
  WHERE organization_id = org_id;

  -- Calculate cumulative stage counts for conversion rates
  -- These count everyone who has REACHED each stage or gone beyond it
  
  -- Count contacts at LEAD or any later stage (passed through LEAD)
  SELECT COUNT(*) INTO count_at_or_beyond_lead
  FROM contacts
  WHERE organization_id = org_id
    AND UPPER(pipeline_stage) IN (
      'LEAD',
      'APPOINTMENT_REQUESTED',
      'APPOINTMENT_SCHEDULED',
      'APPOINTMENT_CANCELLED',
      'PRESENTATION_SCHEDULED',
      'CONTRACT_NEGOTIATIONS',
      'AGREEMENT_IN_PRINCIPLE',
      'CLOSED_WON',
      'CLOSED_LOST',
      'REENGAGEMENT'
    );

  -- Count contacts at APPOINTMENT stages or beyond (passed through APPOINTMENT)
  SELECT COUNT(*) INTO count_at_or_beyond_appointment
  FROM contacts
  WHERE organization_id = org_id
    AND UPPER(pipeline_stage) IN (
      'APPOINTMENT_REQUESTED',
      'APPOINTMENT_SCHEDULED',
      'APPOINTMENT_CANCELLED',
      'PRESENTATION_SCHEDULED',
      'CONTRACT_NEGOTIATIONS',
      'AGREEMENT_IN_PRINCIPLE',
      'CLOSED_WON',
      'CLOSED_LOST',
      'REENGAGEMENT'
    );

  -- Count contacts at APPOINTMENT_SCHEDULED or beyond (for appointment → presentation conversion)
  SELECT COUNT(*) INTO count_at_or_beyond_appointment_scheduled
  FROM contacts
  WHERE organization_id = org_id
    AND UPPER(pipeline_stage) IN (
      'APPOINTMENT_SCHEDULED',
      'APPOINTMENT_CANCELLED',
      'PRESENTATION_SCHEDULED',
      'CONTRACT_NEGOTIATIONS',
      'AGREEMENT_IN_PRINCIPLE',
      'CLOSED_WON',
      'CLOSED_LOST',
      'REENGAGEMENT'
    );

  -- Count contacts at PRESENTATION or beyond
  SELECT COUNT(*) INTO count_at_or_beyond_presentation
  FROM contacts
  WHERE organization_id = org_id
    AND UPPER(pipeline_stage) IN (
      'PRESENTATION_SCHEDULED',
      'CONTRACT_NEGOTIATIONS',
      'AGREEMENT_IN_PRINCIPLE',
      'CLOSED_WON'
    );

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
      -- Prospect → Lead: (contacts that reached Lead or beyond) / (total contacts)
      'prospectToLead', CASE 
        WHEN total_contacts > 0 
        THEN ROUND((count_at_or_beyond_lead::numeric / total_contacts * 100), 2)
        ELSE 0
      END,
      -- Lead → Appointment: (contacts that reached Appointment or beyond) / (contacts that reached Lead or beyond)
      'leadToAppointment', CASE 
        WHEN count_at_or_beyond_lead > 0 
        THEN ROUND((count_at_or_beyond_appointment::numeric / count_at_or_beyond_lead * 100), 2)
        ELSE 0
      END,
      -- Appointment → Presentation: (contacts at Presentation or beyond) / (contacts at Appointment Scheduled or beyond)
      'appointmentToPresentation', CASE 
        WHEN count_at_or_beyond_appointment_scheduled > 0 
        THEN ROUND((count_at_or_beyond_presentation::numeric / count_at_or_beyond_appointment_scheduled * 100), 2)
        ELSE 0
      END
    )
  );
END;
$$ LANGUAGE plpgsql STABLE;

-- Ensure indexes exist for performance
CREATE INDEX IF NOT EXISTS idx_contacts_pipeline_stage ON contacts(pipeline_stage);
CREATE INDEX IF NOT EXISTS idx_contacts_organization_id ON contacts(organization_id);
CREATE INDEX IF NOT EXISTS idx_contacts_location ON contacts(location);
CREATE INDEX IF NOT EXISTS idx_companies_industries ON companies USING GIN(industries);
CREATE INDEX IF NOT EXISTS idx_company_contacts_contact_id ON company_contacts(contact_id);
CREATE INDEX IF NOT EXISTS idx_company_contacts_company_id ON company_contacts(company_id);

COMMENT ON FUNCTION get_sales_pipeline_analytics(TEXT) IS 
'Fixed conversion rate calculation - now uses cumulative stage progression.
Prospect→Lead: % of total contacts that reached Lead or beyond
Lead→Appointment: % of contacts at Lead+ that reached Appointment or beyond  
Appointment→Presentation: % of contacts with scheduled appointments that reached Presentation';

-- Examples of expected behavior:
-- 
-- Scenario 1: Screenshot 3 data (BEFORE FIX was showing 200%!)
-- - 2241 Prospects
-- - 1 Lead
-- - 2 Appointment Requested
-- - 1 Closed Lost
-- 
-- With FIX:
-- - count_at_or_beyond_lead = 1 + 2 + 1 = 4 (Lead, Appt Req, Closed Lost)
-- - count_at_or_beyond_appointment = 2 + 1 = 3 (Appt Req, Closed Lost)
-- - prospectToLead = 4 / 2245 * 100 = 0.18%
-- - leadToAppointment = 3 / 4 * 100 = 75%
--
-- Scenario 2: Screenshot 2 data
-- - 120 Prospects
-- - 19 Lead
-- - 12 Appointment Requested
-- - 2 Appointment Scheduled
-- - 1 Closed Lost
--
-- With FIX:
-- - total = 154
-- - count_at_or_beyond_lead = 19 + 12 + 2 + 1 = 34
-- - count_at_or_beyond_appointment = 12 + 2 + 1 = 15
-- - prospectToLead = 34 / 154 * 100 = 22.08%
-- - leadToAppointment = 15 / 34 * 100 = 44.12%

