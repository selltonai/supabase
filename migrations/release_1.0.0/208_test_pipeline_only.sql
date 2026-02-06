-- Test function that ONLY returns pipeline data to isolate the issue
CREATE OR REPLACE FUNCTION test_pipeline_only(org_id TEXT)
RETURNS JSON AS $$
DECLARE
  pipeline_data JSON;
  total_contacts INTEGER;
BEGIN
  -- Get total contacts for percentage calculation
  SELECT COUNT(*) INTO total_contacts
  FROM contacts
  WHERE organization_id = org_id;

  -- Get pipeline stage distribution - DIRECT AND SIMPLE
  SELECT json_agg(stage_row)
  INTO pipeline_data
  FROM (
    SELECT 
      json_build_object(
        'stage', UPPER(COALESCE(NULLIF(TRIM(pipeline_stage), ''), 'Unknown')),
        'count', COUNT(*)::integer,
        'percentage', ROUND((COUNT(*)::numeric / total_contacts * 100), 2)
      ) as stage_row
    FROM contacts
    WHERE organization_id = org_id
    GROUP BY UPPER(COALESCE(NULLIF(TRIM(pipeline_stage), ''), 'Unknown'))
    ORDER BY COUNT(*) DESC
  ) stages;

  RETURN COALESCE(pipeline_data, '[]'::json);
END;
$$ LANGUAGE plpgsql STABLE;

-- Test it:
-- SELECT test_pipeline_only('org_32BKjMNKEpb2wtrpswAogimVMkV');


