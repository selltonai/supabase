-- Create a unified function for all dashboard statistics
-- This avoids multiple round-trips and fetches all key metrics in one go.

CREATE OR REPLACE FUNCTION get_dashboard_stats(org_id UUID)
RETURNS JSON AS $$
DECLARE
  result JSON;
  task_stats JSON;
  companies_total INT;
  contacts_total INT;
BEGIN
  -- We can run these queries in a single transaction context, which is very efficient.
  SELECT get_task_status_counts(org_id) INTO task_stats;
  
  SELECT COUNT(*) INTO companies_total
  FROM companies
  WHERE organization_id = org_id;
  
  SELECT COUNT(*) INTO contacts_total
  FROM contacts
  WHERE organization_id = org_id;

  -- Combine all stats into a single JSON object to be returned
  SELECT json_build_object(
    'tasks', task_stats,
    'companies', json_build_object('total', COALESCE(companies_total, 0)),
    'contacts', json_build_object('total', COALESCE(contacts_total, 0))
  ) INTO result;
  
  RETURN result;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION get_dashboard_stats(UUID) IS 'Provides a unified set of statistics for the main dashboard KPIs, including tasks, companies, and contacts counts.';


