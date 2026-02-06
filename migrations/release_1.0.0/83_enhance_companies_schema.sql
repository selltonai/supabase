-- Migration: Enhance Companies Schema for Rich Company Data
-- Purpose: Add support for B2B enrichment, ICP scoring, deep research, and enhanced contact data
-- Date: 2025-01-13

-- Add new columns to companies table for enhanced data
ALTER TABLE companies 
  -- Basic company enrichment data
  ADD COLUMN IF NOT EXISTS employee_count INTEGER,
  ADD COLUMN IF NOT EXISTS location TEXT, -- Full location string
  ADD COLUMN IF NOT EXISTS phone TEXT,
  ADD COLUMN IF NOT EXISTS tagline TEXT,
  ADD COLUMN IF NOT EXISTS logo_url TEXT,
  ADD COLUMN IF NOT EXISTS cover_image_url TEXT,
  ADD COLUMN IF NOT EXISTS universal_name TEXT, -- LinkedIn universal name
  ADD COLUMN IF NOT EXISTS object_urn TEXT, -- LinkedIn object URN
  ADD COLUMN IF NOT EXISTS company_type TEXT, -- e.g., "Public Company"
  ADD COLUMN IF NOT EXISTS followers_count INTEGER,
  ADD COLUMN IF NOT EXISTS specialties TEXT[], -- Array of company specialties
  ADD COLUMN IF NOT EXISTS hashtags TEXT[], -- Company hashtags
  
  -- Enhanced location data
  ADD COLUMN IF NOT EXISTS postal_code TEXT,
  ADD COLUMN IF NOT EXISTS address_line1 TEXT,
  ADD COLUMN IF NOT EXISTS address_line2 TEXT,
  ADD COLUMN IF NOT EXISTS geographic_area TEXT,
  
  -- Funding and business data
  ADD COLUMN IF NOT EXISTS funding_data JSONB, -- Store complex funding information
  
  -- B2B enrichment result (full API response)
  ADD COLUMN IF NOT EXISTS b2b_result JSONB,
  
  -- ICP scoring data
  ADD COLUMN IF NOT EXISTS icp_score_total DECIMAL(5,2),
  ADD COLUMN IF NOT EXISTS icp_score_tier TEXT, -- e.g., "Tier 1", "Tier 2", "Tier 3"
  ADD COLUMN IF NOT EXISTS icp_confidence_level DECIMAL(3,2),
  ADD COLUMN IF NOT EXISTS icp_component_scores JSONB, -- Individual component scores
  ADD COLUMN IF NOT EXISTS icp_reasoning JSONB, -- Detailed reasoning for each component
  ADD COLUMN IF NOT EXISTS icp_recommendations TEXT[], -- Array of recommendations
  ADD COLUMN IF NOT EXISTS icp_data_completeness DECIMAL(3,2),
  
  -- Deep research data
  ADD COLUMN IF NOT EXISTS deep_research JSONB, -- Full deep research results
  ADD COLUMN IF NOT EXISTS key_insights TEXT[], -- Array of key insights
  ADD COLUMN IF NOT EXISTS recent_developments TEXT[], -- Array of recent developments
  ADD COLUMN IF NOT EXISTS growth_signals TEXT[], -- Array of growth signals
  ADD COLUMN IF NOT EXISTS company_profile_summary TEXT,
  
  -- Research modules data (structured research information)
  ADD COLUMN IF NOT EXISTS research_modules JSONB, -- Complete research modules with company_overview, icp_analysis, growth_signals, recent_news, company_profile
  
  -- Processing metadata
  ADD COLUMN IF NOT EXISTS contacts_found INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS processing_status TEXT DEFAULT 'pending', -- pending, processing, completed, failed
  ADD COLUMN IF NOT EXISTS source TEXT, -- e.g., "csv", "manual", "api"
  ADD COLUMN IF NOT EXISTS extraction_timestamp TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS research_duration TEXT, -- Duration of research process
  ADD COLUMN IF NOT EXISTS api_usage JSONB; -- Track API usage for this company

-- Create indexes for performance on new columns
CREATE INDEX IF NOT EXISTS idx_companies_employee_count ON companies(employee_count);
CREATE INDEX IF NOT EXISTS idx_companies_icp_score_total ON companies(icp_score_total);
CREATE INDEX IF NOT EXISTS idx_companies_icp_score_tier ON companies(icp_score_tier);
CREATE INDEX IF NOT EXISTS idx_companies_processing_status ON companies(processing_status);
CREATE INDEX IF NOT EXISTS idx_companies_source ON companies(source);
CREATE INDEX IF NOT EXISTS idx_companies_extraction_timestamp ON companies(extraction_timestamp);
CREATE INDEX IF NOT EXISTS idx_companies_universal_name ON companies(universal_name);
CREATE INDEX IF NOT EXISTS idx_companies_object_urn ON companies(object_urn);

-- Create GIN indexes for JSONB columns for efficient querying
CREATE INDEX IF NOT EXISTS idx_companies_b2b_result_gin ON companies USING GIN (b2b_result);
CREATE INDEX IF NOT EXISTS idx_companies_icp_component_scores_gin ON companies USING GIN (icp_component_scores);
CREATE INDEX IF NOT EXISTS idx_companies_icp_reasoning_gin ON companies USING GIN (icp_reasoning);
CREATE INDEX IF NOT EXISTS idx_companies_deep_research_gin ON companies USING GIN (deep_research);
CREATE INDEX IF NOT EXISTS idx_companies_funding_data_gin ON companies USING GIN (funding_data);
CREATE INDEX IF NOT EXISTS idx_companies_api_usage_gin ON companies USING GIN (api_usage);
CREATE INDEX IF NOT EXISTS idx_companies_research_modules_gin ON companies USING GIN (research_modules);

-- Add comments for documentation
COMMENT ON COLUMN companies.employee_count IS 'Number of employees in the company';
COMMENT ON COLUMN companies.phone IS 'Company phone number';
COMMENT ON COLUMN companies.tagline IS 'Company tagline or slogan';
COMMENT ON COLUMN companies.logo_url IS 'URL to company logo image';
COMMENT ON COLUMN companies.cover_image_url IS 'URL to company cover/banner image';
COMMENT ON COLUMN companies.universal_name IS 'LinkedIn universal name identifier';
COMMENT ON COLUMN companies.object_urn IS 'LinkedIn object URN identifier';
COMMENT ON COLUMN companies.company_type IS 'Type of company (e.g., Public Company, Private Company)';
COMMENT ON COLUMN companies.followers_count IS 'Number of LinkedIn followers';
COMMENT ON COLUMN companies.specialties IS 'Array of company specialties and focus areas';
COMMENT ON COLUMN companies.hashtags IS 'Array of company hashtags';
COMMENT ON COLUMN companies.postal_code IS 'Postal/ZIP code of company address';
COMMENT ON COLUMN companies.address_line1 IS 'First line of company address';
COMMENT ON COLUMN companies.address_line2 IS 'Second line of company address';
COMMENT ON COLUMN companies.geographic_area IS 'Geographic area/region of company location';
COMMENT ON COLUMN companies.funding_data IS 'Detailed funding information including rounds, investors, amounts';
COMMENT ON COLUMN companies.b2b_result IS 'Full B2B enrichment API response data';
COMMENT ON COLUMN companies.icp_score_total IS 'Total ICP (Ideal Customer Profile) score out of 100';
COMMENT ON COLUMN companies.icp_score_tier IS 'ICP tier classification (Tier 1, Tier 2, Tier 3)';
COMMENT ON COLUMN companies.icp_confidence_level IS 'Confidence level of ICP scoring (0-1)';
COMMENT ON COLUMN companies.icp_component_scores IS 'Individual component scores for ICP analysis';
COMMENT ON COLUMN companies.icp_reasoning IS 'Detailed reasoning for each ICP component score';
COMMENT ON COLUMN companies.icp_recommendations IS 'Array of recommendations based on ICP analysis';
COMMENT ON COLUMN companies.icp_data_completeness IS 'Data completeness score for ICP analysis (0-1)';
COMMENT ON COLUMN companies.deep_research IS 'Full deep research results including growth signals, news, etc.';
COMMENT ON COLUMN companies.key_insights IS 'Array of key insights from deep research';
COMMENT ON COLUMN companies.recent_developments IS 'Array of recent company developments and news';
COMMENT ON COLUMN companies.growth_signals IS 'Array of growth signals and business intent indicators';
COMMENT ON COLUMN companies.company_profile_summary IS 'Summary of company profile from research';
COMMENT ON COLUMN companies.research_modules IS 'Complete research modules data including company_overview, icp_analysis, growth_signals, recent_news, and company_profile with provider responses and combined analysis';
COMMENT ON COLUMN companies.contacts_found IS 'Number of contacts found for this company';
COMMENT ON COLUMN companies.processing_status IS 'Status of company data processing (pending, processing, completed, failed)';
COMMENT ON COLUMN companies.source IS 'Source of company data (csv, manual, api, etc.)';
COMMENT ON COLUMN companies.extraction_timestamp IS 'Timestamp when data was extracted/processed';
COMMENT ON COLUMN companies.research_duration IS 'Duration of the research/analysis process';
COMMENT ON COLUMN companies.api_usage IS 'API usage statistics for this company analysis';

-- Create a function to update ICP score tier based on total score
CREATE OR REPLACE FUNCTION update_icp_tier()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.icp_score_total IS NOT NULL THEN
    NEW.icp_score_tier := CASE
      WHEN NEW.icp_score_total >= 80 THEN 'Tier 1'
      WHEN NEW.icp_score_total >= 60 THEN 'Tier 2'
      ELSE 'Tier 3'
    END;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to automatically update ICP tier when score changes
DROP TRIGGER IF EXISTS trigger_update_icp_tier ON companies;
CREATE TRIGGER trigger_update_icp_tier
  BEFORE INSERT OR UPDATE OF icp_score_total ON companies
  FOR EACH ROW
  EXECUTE FUNCTION update_icp_tier();

-- Create a view for company analytics
CREATE OR REPLACE VIEW company_analytics AS
SELECT 
  c.id,
  c.organization_id,
  c.name,
  c.domain,
  c.industry,
  c.employee_count,
  c.icp_score_total,
  c.icp_score_tier,
  c.icp_confidence_level,
  c.contacts_found,
  c.processing_status,
  c.source,
  c.created_at,
  c.extraction_timestamp,
  -- Extract key metrics from JSONB fields
  (c.icp_component_scores->>'industry_fit')::DECIMAL AS industry_fit_score,
  (c.icp_component_scores->>'company_size_revenue')::DECIMAL AS company_size_score,
  (c.icp_component_scores->>'tech_stack_compatibility')::DECIMAL AS tech_stack_score,
  (c.icp_component_scores->>'engagement_intent')::DECIMAL AS engagement_score,
  (c.icp_component_scores->>'customer_success_match')::DECIMAL AS customer_success_score,
  (c.icp_component_scores->>'strategic_value')::DECIMAL AS strategic_value_score,
  -- Extract research modules summary data
  (c.research_modules->'company_overview'->>'summary') AS company_overview_summary,
  (c.research_modules->'icp_analysis'->>'summary') AS icp_analysis_summary,
  (c.research_modules->'growth_signals'->>'summary') AS growth_signals_summary,
  (c.research_modules->'recent_news'->>'summary') AS recent_news_summary,
  (c.research_modules->'company_profile'->>'summary') AS company_profile_summary_research,
  -- Extract key findings arrays
  COALESCE(
    ARRAY(SELECT jsonb_array_elements_text(c.research_modules->'company_overview'->'key_findings')), 
    ARRAY[]::TEXT[]
  ) AS company_overview_key_findings,
  COALESCE(
    ARRAY(SELECT jsonb_array_elements_text(c.research_modules->'icp_analysis'->'key_findings')), 
    ARRAY[]::TEXT[]
  ) AS icp_analysis_key_findings,
  COALESCE(
    ARRAY(SELECT jsonb_array_elements_text(c.research_modules->'growth_signals'->'key_findings')), 
    ARRAY[]::TEXT[]
  ) AS growth_signals_key_findings,
  -- Count contacts for this company
  COUNT(contacts.id) AS total_contacts
FROM companies c
LEFT JOIN contacts ON contacts.company_id = c.id
GROUP BY c.id, c.organization_id, c.name, c.domain, c.industry, c.employee_count, 
         c.icp_score_total, c.icp_score_tier, c.icp_confidence_level, c.contacts_found,
         c.processing_status, c.source, c.created_at, c.extraction_timestamp, c.icp_component_scores, c.research_modules;

COMMENT ON VIEW company_analytics IS 'Analytics view for company data with extracted metrics and contact counts'; 