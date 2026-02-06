-- Migration: Add ICP columns to campaigns table
-- Description: Moves ICP settings from metadata to dedicated columns for better structure and performance
-- Author: System
-- Date: 2025-02-04

-- Add ICP columns to campaigns table (matching organization_settings structure)
ALTER TABLE campaigns
  ADD COLUMN IF NOT EXISTS icp_min_employees INTEGER,
  ADD COLUMN IF NOT EXISTS icp_max_employees INTEGER,
  ADD COLUMN IF NOT EXISTS icp_sales_process TEXT[] DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS icp_industries TEXT[] DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS icp_job_titles TEXT[] DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS icp_primary_regions TEXT[] DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS icp_secondary_regions TEXT[] DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS icp_focus_areas TEXT[] DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS icp_pain_points TEXT[] DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS icp_keywords TEXT[] DEFAULT '{}';

-- Create indexes for array columns for better performance
CREATE INDEX IF NOT EXISTS idx_campaigns_icp_industries ON campaigns USING GIN (icp_industries);
CREATE INDEX IF NOT EXISTS idx_campaigns_icp_job_titles ON campaigns USING GIN (icp_job_titles);
CREATE INDEX IF NOT EXISTS idx_campaigns_icp_regions ON campaigns USING GIN (icp_primary_regions);

-- Migrate existing ICP data from metadata to new columns
DO $$
DECLARE
  campaign_record RECORD;
  icp_data JSONB;
BEGIN
  -- Loop through all campaigns that have ICP settings in metadata
  FOR campaign_record IN 
    SELECT id, metadata
    FROM campaigns
    WHERE metadata IS NOT NULL 
    AND metadata->'icp_settings' IS NOT NULL
  LOOP
    icp_data := campaign_record.metadata->'icp_settings';
    
    -- Update campaign with ICP data from metadata
    UPDATE campaigns
    SET 
      icp_min_employees = COALESCE((icp_data->>'icp_min_employees')::INTEGER, 11),
      icp_max_employees = COALESCE((icp_data->>'icp_max_employees')::INTEGER, 500),
      icp_sales_process = CASE
        WHEN jsonb_typeof(icp_data->'icp_sales_process') = 'array' THEN
          COALESCE(ARRAY(SELECT jsonb_array_elements_text(icp_data->'icp_sales_process')), '{}'::TEXT[])
        ELSE '{}'::TEXT[]
      END,
      icp_industries = CASE
        WHEN jsonb_typeof(icp_data->'icp_industries') = 'array' THEN
          COALESCE(ARRAY(SELECT jsonb_array_elements_text(icp_data->'icp_industries')), '{}'::TEXT[])
        ELSE '{}'::TEXT[]
      END,
      icp_job_titles = CASE
        WHEN jsonb_typeof(icp_data->'icp_job_titles') = 'array' THEN
          COALESCE(ARRAY(SELECT jsonb_array_elements_text(icp_data->'icp_job_titles')), '{}'::TEXT[])
        ELSE '{}'::TEXT[]
      END,
      icp_primary_regions = CASE
        WHEN jsonb_typeof(icp_data->'icp_primary_regions') = 'array' THEN
          COALESCE(ARRAY(SELECT jsonb_array_elements_text(icp_data->'icp_primary_regions')), '{}'::TEXT[])
        ELSE '{}'::TEXT[]
      END,
      icp_secondary_regions = CASE
        WHEN jsonb_typeof(icp_data->'icp_secondary_regions') = 'array' THEN
          COALESCE(ARRAY(SELECT jsonb_array_elements_text(icp_data->'icp_secondary_regions')), '{}'::TEXT[])
        ELSE '{}'::TEXT[]
      END,
      icp_focus_areas = CASE
        WHEN jsonb_typeof(icp_data->'icp_focus_areas') = 'array' THEN
          COALESCE(ARRAY(SELECT jsonb_array_elements_text(icp_data->'icp_focus_areas')), '{}'::TEXT[])
        ELSE '{}'::TEXT[]
      END,
      icp_pain_points = CASE
        WHEN jsonb_typeof(icp_data->'icp_pain_points') = 'array' THEN
          COALESCE(ARRAY(SELECT jsonb_array_elements_text(icp_data->'icp_pain_points')), '{}'::TEXT[])
        ELSE '{}'::TEXT[]
      END,
      icp_keywords = CASE
        WHEN jsonb_typeof(icp_data->'icp_keywords') = 'array' THEN
          COALESCE(ARRAY(SELECT jsonb_array_elements_text(icp_data->'icp_keywords')), '{}'::TEXT[])
        ELSE '{}'::TEXT[]
      END
    WHERE id = campaign_record.id;
  END LOOP;
END $$;

-- Add table to track campaign-specific LinkedIn URLs (similar to organization_icp_linkedin_urls)
CREATE TABLE IF NOT EXISTS campaign_icp_linkedin_urls (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  campaign_id UUID NOT NULL REFERENCES campaigns(id) ON DELETE CASCADE,
  organization_id TEXT NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
  url TEXT NOT NULL,
  url_type TEXT NOT NULL CHECK (url_type IN ('current_customer', 'ideal_customer', 'ideal_person', 'exclusion')),
  added_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(campaign_id, url, url_type)
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_campaign_icp_linkedin_campaign ON campaign_icp_linkedin_urls(campaign_id);
CREATE INDEX IF NOT EXISTS idx_campaign_icp_linkedin_org ON campaign_icp_linkedin_urls(organization_id);
CREATE INDEX IF NOT EXISTS idx_campaign_icp_linkedin_url ON campaign_icp_linkedin_urls(url);

-- Enable RLS
ALTER TABLE campaign_icp_linkedin_urls ENABLE ROW LEVEL SECURITY;

-- Create RLS policies for campaign LinkedIn URLs table
CREATE POLICY "Users can view their campaign's LinkedIn URLs"
  ON campaign_icp_linkedin_urls
  FOR SELECT
  USING (
    organization_id IN (
      SELECT organization_id FROM user_organizations 
      WHERE user_id = auth.uid()::text
    )
  );

CREATE POLICY "Users can insert LinkedIn URLs for their campaigns"
  ON campaign_icp_linkedin_urls
  FOR INSERT
  WITH CHECK (
    organization_id IN (
      SELECT organization_id FROM user_organizations 
      WHERE user_id = auth.uid()::text
    )
  );

CREATE POLICY "Users can update their campaign's LinkedIn URLs"
  ON campaign_icp_linkedin_urls
  FOR UPDATE
  USING (
    organization_id IN (
      SELECT organization_id FROM user_organizations 
      WHERE user_id = auth.uid()::text
    )
  );

CREATE POLICY "Users can delete their campaign's LinkedIn URLs"
  ON campaign_icp_linkedin_urls
  FOR DELETE
  USING (
    organization_id IN (
      SELECT organization_id FROM user_organizations 
      WHERE user_id = auth.uid()::text
    )
  );

-- Add comments for documentation
COMMENT ON COLUMN campaigns.icp_min_employees IS 'Minimum number of employees for target companies in this campaign';
COMMENT ON COLUMN campaigns.icp_max_employees IS 'Maximum number of employees for target companies in this campaign';
COMMENT ON COLUMN campaigns.icp_sales_process IS 'Sales process characteristics for this campaign';
COMMENT ON COLUMN campaigns.icp_industries IS 'Target industries for this campaign';
COMMENT ON COLUMN campaigns.icp_job_titles IS 'Preferred job titles of prospects for this campaign';
COMMENT ON COLUMN campaigns.icp_primary_regions IS 'Primary geographic regions to target in this campaign';
COMMENT ON COLUMN campaigns.icp_secondary_regions IS 'Secondary geographic regions to target in this campaign';
COMMENT ON COLUMN campaigns.icp_focus_areas IS 'Specific focus areas or niches for this campaign';
COMMENT ON COLUMN campaigns.icp_pain_points IS 'Common pain points of target prospects for this campaign';
COMMENT ON COLUMN campaigns.icp_keywords IS 'Custom keywords/tags for this campaign';

COMMENT ON TABLE campaign_icp_linkedin_urls IS 'LinkedIn URLs for campaign-specific ICP settings';
COMMENT ON COLUMN campaign_icp_linkedin_urls.url_type IS 'Type of LinkedIn URL: current_customer, ideal_customer, ideal_person, or exclusion';