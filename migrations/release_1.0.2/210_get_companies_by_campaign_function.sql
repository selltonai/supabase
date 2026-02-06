-- First drop the existing function
DROP FUNCTION IF EXISTS get_companies_by_campaign(text,uuid,text,text,text,text,integer,integer);

-- Then create the new function with correct types
CREATE OR REPLACE FUNCTION get_companies_by_campaign(
  p_organization_id TEXT,
  p_campaign_id UUID,
  p_status TEXT DEFAULT NULL,
  p_search TEXT DEFAULT NULL,
  p_sort_by TEXT DEFAULT 'name',
  p_sort_order TEXT DEFAULT 'asc',
  p_page INTEGER DEFAULT 1,
  p_limit INTEGER DEFAULT 50
)
RETURNS TABLE (
  id UUID,
  organization_id TEXT,
  name TEXT,
  website TEXT,
  size TEXT,
  linkedin_url TEXT,
  description TEXT,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ,
  used_for_outreach BOOLEAN,
  phone TEXT,
  employee_count INTEGER,
  logo TEXT,
  location TEXT,
  industries TEXT[],
  icp_score JSONB,
  deep_research JSONB,
  outreach_strategy JSONB,
  universal_name TEXT,
  company_type TEXT,
  cover TEXT,
  tagline TEXT,
  founded_year INTEGER,
  object_urn BIGINT,
  followers INTEGER,
  locations JSONB,
  funding_data JSONB,
  specialities TEXT[],
  hashtags TEXT[],
  processing_status TEXT,
  b2b_result JSONB,
  blocked_by_icp BOOLEAN,
  total_count BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_offset INTEGER;
  v_total BIGINT;
BEGIN
  v_offset := (p_page - 1) * p_limit;
  
  SELECT COUNT(DISTINCT c.id) INTO v_total
  FROM companies c
  INNER JOIN campaign_companies cc ON c.id = cc.company_id
  WHERE c.organization_id = p_organization_id
    AND cc.campaign_id = p_campaign_id
    AND cc.organization_id = p_organization_id
    AND (
      p_status IS NULL
      OR (p_status = 'approved' AND c.processing_status = 'approved' AND COALESCE(c.blocked_by_icp, false) = false)
      OR (p_status = 'processing' AND c.processing_status IN ('processing', 'pending'))
      OR (p_status = 'processed' AND (c.processing_status IN ('processed', 'approved', 'declined') OR c.blocked_by_icp = true))
      OR (p_status = 'declined' AND c.processing_status = 'declined')
      OR (p_status = 'blocked_by_icp' AND c.blocked_by_icp = true)
      OR (p_status = 'failed' AND c.processing_status = 'failed')
      OR (p_status = 'scheduled' AND c.processing_status = 'scheduled')
    )
    AND (p_search IS NULL OR p_search = '' OR c.name ILIKE '%' || p_search || '%' OR c.location ILIKE '%' || p_search || '%');

  RETURN QUERY
  SELECT 
    c.id, c.organization_id, c.name, c.website, c.size, c.linkedin_url, c.description,
    c.created_at, c.updated_at, c.used_for_outreach, c.phone, c.employee_count, c.logo,
    c.location, c.industries, c.icp_score, c.deep_research, c.outreach_strategy,
    c.universal_name, c.company_type, c.cover, c.tagline, c.founded_year, c.object_urn,
    c.followers, c.locations, c.funding_data, c.specialities, c.hashtags,
    c.processing_status, c.b2b_result, c.blocked_by_icp, v_total
  FROM companies c
  INNER JOIN campaign_companies cc ON c.id = cc.company_id
  WHERE c.organization_id = p_organization_id
    AND cc.campaign_id = p_campaign_id
    AND cc.organization_id = p_organization_id
    AND (
      p_status IS NULL
      OR (p_status = 'approved' AND c.processing_status = 'approved' AND COALESCE(c.blocked_by_icp, false) = false)
      OR (p_status = 'processing' AND c.processing_status IN ('processing', 'pending'))
      OR (p_status = 'processed' AND (c.processing_status IN ('processed', 'approved', 'declined') OR c.blocked_by_icp = true))
      OR (p_status = 'declined' AND c.processing_status = 'declined')
      OR (p_status = 'blocked_by_icp' AND c.blocked_by_icp = true)
      OR (p_status = 'failed' AND c.processing_status = 'failed')
      OR (p_status = 'scheduled' AND c.processing_status = 'scheduled')
    )
    AND (p_search IS NULL OR p_search = '' OR c.name ILIKE '%' || p_search || '%' OR c.location ILIKE '%' || p_search || '%')
  ORDER BY
    CASE WHEN p_sort_by = 'name' AND p_sort_order = 'asc' THEN c.name END ASC,
    CASE WHEN p_sort_by = 'name' AND p_sort_order = 'desc' THEN c.name END DESC,
    CASE WHEN p_sort_by = 'created_at' AND p_sort_order = 'asc' THEN c.created_at END ASC,
    CASE WHEN p_sort_by = 'created_at' AND p_sort_order = 'desc' THEN c.created_at END DESC,
    c.name ASC
  LIMIT p_limit OFFSET v_offset;
END;
$$;

GRANT EXECUTE ON FUNCTION get_companies_by_campaign TO authenticated;
GRANT EXECUTE ON FUNCTION get_companies_by_campaign TO service_role;