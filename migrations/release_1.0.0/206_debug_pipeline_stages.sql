-- Debug function to see what's happening with pipeline stages
CREATE OR REPLACE FUNCTION debug_pipeline_stages(org_id TEXT)
RETURNS TABLE (
  stage TEXT,
  count BIGINT,
  raw_stages TEXT[]
) AS $$
BEGIN
  RETURN QUERY
  WITH raw_data AS (
    SELECT 
      pipeline_stage,
      COUNT(*) as cnt
    FROM contacts
    WHERE organization_id = org_id
    GROUP BY pipeline_stage
  ),
  normalized_data AS (
    SELECT 
      CASE 
        WHEN pipeline_stage IS NULL OR pipeline_stage = '' THEN 'Unknown'
        ELSE UPPER(TRIM(pipeline_stage))
      END as normalized_stage,
      COUNT(*) as cnt
    FROM contacts
    WHERE organization_id = org_id
    GROUP BY CASE 
      WHEN pipeline_stage IS NULL OR pipeline_stage = '' THEN 'Unknown'
      ELSE UPPER(TRIM(pipeline_stage))
    END
  )
  SELECT 
    nd.normalized_stage as stage,
    nd.cnt as count,
    ARRAY_AGG(DISTINCT rd.pipeline_stage) as raw_stages
  FROM normalized_data nd
  LEFT JOIN raw_data rd ON (
    CASE 
      WHEN rd.pipeline_stage IS NULL OR rd.pipeline_stage = '' THEN 'Unknown'
      ELSE UPPER(TRIM(rd.pipeline_stage))
    END = nd.normalized_stage
  )
  GROUP BY nd.normalized_stage, nd.cnt
  ORDER BY nd.cnt DESC;
END;
$$ LANGUAGE plpgsql STABLE;

-- Test query to run after creating the function
-- Replace 'YOUR_ORG_ID' with your actual organization ID
-- SELECT * FROM debug_pipeline_stages('YOUR_ORG_ID');


