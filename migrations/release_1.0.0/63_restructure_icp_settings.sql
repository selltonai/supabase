-- Migration to restructure ICP settings from JSONB to individual columns
-- This provides better type safety, performance, and cleaner structure

-- First, add new columns to organization_settings
ALTER TABLE public.organization_settings
  ADD COLUMN IF NOT EXISTS icp_min_employees INTEGER DEFAULT 11,
  ADD COLUMN IF NOT EXISTS icp_max_employees INTEGER DEFAULT 500,
  ADD COLUMN IF NOT EXISTS icp_sales_process TEXT[] DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS icp_industries TEXT[] DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS icp_job_titles TEXT[] DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS icp_primary_regions TEXT[] DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS icp_secondary_regions TEXT[] DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS icp_focus_areas TEXT[] DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS icp_pain_points TEXT[] DEFAULT '{}';

-- Create table for LinkedIn URLs with proper categorization
CREATE TABLE IF NOT EXISTS public.organization_icp_linkedin_urls (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  organization_id TEXT NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  url TEXT NOT NULL,
  url_type TEXT NOT NULL CHECK (url_type IN ('current_customer', 'ideal_customer', 'ideal_person', 'exclusion')),
  added_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(organization_id, url, url_type)
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_icp_linkedin_org_type ON public.organization_icp_linkedin_urls(organization_id, url_type);
CREATE INDEX IF NOT EXISTS idx_icp_linkedin_url ON public.organization_icp_linkedin_urls(url);

-- Enable RLS
ALTER TABLE public.organization_icp_linkedin_urls ENABLE ROW LEVEL SECURITY;

-- Create RLS policies for LinkedIn URLs table
DROP POLICY IF EXISTS "Users can view their organization's LinkedIn URLs" ON public.organization_icp_linkedin_urls;
CREATE POLICY "Users can view their organization's LinkedIn URLs"
  ON public.organization_icp_linkedin_urls
  FOR SELECT
  USING (
    organization_id IN (
      SELECT organization_id FROM public.user_organizations 
      WHERE user_id = auth.uid()::text
    )
  );

DROP POLICY IF EXISTS "Users can insert LinkedIn URLs for their organization" ON public.organization_icp_linkedin_urls;
CREATE POLICY "Users can insert LinkedIn URLs for their organization"
  ON public.organization_icp_linkedin_urls
  FOR INSERT
  WITH CHECK (
    organization_id IN (
      SELECT organization_id FROM public.user_organizations 
      WHERE user_id = auth.uid()::text
    )
  );

DROP POLICY IF EXISTS "Users can update their organization's LinkedIn URLs" ON public.organization_icp_linkedin_urls;
CREATE POLICY "Users can update their organization's LinkedIn URLs"
  ON public.organization_icp_linkedin_urls
  FOR UPDATE
  USING (
    organization_id IN (
      SELECT organization_id FROM public.user_organizations 
      WHERE user_id = auth.uid()::text
    )
  );

DROP POLICY IF EXISTS "Users can delete their organization's LinkedIn URLs" ON public.organization_icp_linkedin_urls;
CREATE POLICY "Users can delete their organization's LinkedIn URLs"
  ON public.organization_icp_linkedin_urls
  FOR DELETE
  USING (
    organization_id IN (
      SELECT organization_id FROM public.user_organizations 
      WHERE user_id = auth.uid()::text
    )
  );

-- Migrate existing data from JSONB to new structure
DO $$
DECLARE
  org_record RECORD;
  linkedin_url TEXT;
BEGIN
  -- Check if icp_settings column exists before proceeding
  IF EXISTS (
    SELECT 1 
    FROM information_schema.columns 
    WHERE table_name = 'organization_settings' 
    AND column_name = 'icp_settings'
  ) THEN
    -- Migrate each organization's ICP settings
    FOR org_record IN 
      SELECT id, organization_id, icp_settings
      FROM public.organization_settings
      WHERE icp_settings IS NOT NULL
    LOOP
      -- Update scalar and array fields
      UPDATE public.organization_settings
      SET 
        icp_min_employees = CASE
          WHEN jsonb_typeof(org_record.icp_settings->'company_criteria') = 'object' AND jsonb_typeof(org_record.icp_settings->'company_criteria'->'company_size') = 'object' THEN
            COALESCE((org_record.icp_settings->'company_criteria'->'company_size'->>'min_employees')::INTEGER, 11)
          ELSE 11
        END,
        icp_max_employees = CASE
          WHEN jsonb_typeof(org_record.icp_settings->'company_criteria') = 'object' AND jsonb_typeof(org_record.icp_settings->'company_criteria'->'company_size') = 'object' THEN
            COALESCE((org_record.icp_settings->'company_criteria'->'company_size'->>'max_employees')::INTEGER, 500)
          ELSE 500
        END,
        icp_sales_process = CASE
          WHEN jsonb_typeof(org_record.icp_settings->'company_criteria') = 'object' AND jsonb_typeof(org_record.icp_settings->'company_criteria'->'sales_process') = 'array' THEN
            COALESCE(ARRAY(SELECT jsonb_array_elements_text(org_record.icp_settings->'company_criteria'->'sales_process')), '{}'::TEXT[])
          ELSE '{}'::TEXT[]
        END,
        icp_industries = CASE
          WHEN jsonb_typeof(org_record.icp_settings->'industries') = 'object' THEN
            COALESCE(ARRAY(SELECT jsonb_object_keys(org_record.icp_settings->'industries')), '{}'::TEXT[])
          WHEN jsonb_typeof(org_record.icp_settings->'industries') = 'array' THEN
            COALESCE(ARRAY(SELECT jsonb_array_elements_text(org_record.icp_settings->'industries')), '{}'::TEXT[])
          ELSE '{}'::TEXT[]
        END,
        icp_job_titles = CASE
          WHEN jsonb_typeof(org_record.icp_settings->'preferred_job_titles') = 'array' THEN
            COALESCE(ARRAY(SELECT jsonb_array_elements_text(org_record.icp_settings->'preferred_job_titles')), '{}'::TEXT[])
          ELSE '{}'::TEXT[]
        END,
        icp_primary_regions = CASE
          WHEN jsonb_typeof(org_record.icp_settings->'geography') = 'object' AND jsonb_typeof(org_record.icp_settings->'geography'->'primary_regions') = 'array' THEN
            COALESCE(ARRAY(SELECT jsonb_array_elements_text(org_record.icp_settings->'geography'->'primary_regions')), '{}'::TEXT[])
          ELSE '{}'::TEXT[]
        END,
        icp_secondary_regions = CASE
          WHEN jsonb_typeof(org_record.icp_settings->'geography') = 'object' AND jsonb_typeof(org_record.icp_settings->'geography'->'secondary_regions') = 'array' THEN
            COALESCE(ARRAY(SELECT jsonb_array_elements_text(org_record.icp_settings->'geography'->'secondary_regions')), '{}'::TEXT[])
          ELSE '{}'::TEXT[]
        END,
        icp_focus_areas = CASE
          WHEN jsonb_typeof(org_record.icp_settings->'geography') = 'object' AND jsonb_typeof(org_record.icp_settings->'geography'->'focus_areas') = 'array' THEN
            COALESCE(ARRAY(SELECT jsonb_array_elements_text(org_record.icp_settings->'geography'->'focus_areas')), '{}'::TEXT[])
          ELSE '{}'::TEXT[]
        END,
        icp_pain_points = CASE
          WHEN jsonb_typeof(org_record.icp_settings->'pain_points') = 'array' THEN
            COALESCE(ARRAY(SELECT jsonb_array_elements_text(org_record.icp_settings->'pain_points')), '{}'::TEXT[])
          ELSE '{}'::TEXT[]
        END
      WHERE id = org_record.id;

      -- Migrate LinkedIn URLs to the new table
      
      -- Current customers
      IF org_record.icp_settings->'current_customers' IS NOT NULL AND jsonb_typeof(org_record.icp_settings->'current_customers') = 'array' THEN
        FOR linkedin_url IN 
          SELECT jsonb_array_elements_text(org_record.icp_settings->'current_customers')
        LOOP
          INSERT INTO public.organization_icp_linkedin_urls (organization_id, url, url_type)
          VALUES (org_record.organization_id, linkedin_url, 'current_customer')
          ON CONFLICT (organization_id, url, url_type) DO NOTHING;
        END LOOP;
      END IF;

      -- Ideal customers
      IF org_record.icp_settings->'ideal_customers' IS NOT NULL AND jsonb_typeof(org_record.icp_settings->'ideal_customers') = 'array' THEN
        FOR linkedin_url IN 
          SELECT jsonb_array_elements_text(org_record.icp_settings->'ideal_customers')
        LOOP
          INSERT INTO public.organization_icp_linkedin_urls (organization_id, url, url_type)
          VALUES (org_record.organization_id, linkedin_url, 'ideal_customer')
          ON CONFLICT (organization_id, url, url_type) DO NOTHING;
        END LOOP;
      END IF;

      -- Ideal persons
      IF org_record.icp_settings->'ideal_persons' IS NOT NULL AND jsonb_typeof(org_record.icp_settings->'ideal_persons') = 'array' THEN
        FOR linkedin_url IN 
          SELECT jsonb_array_elements_text(org_record.icp_settings->'ideal_persons')
        LOOP
          INSERT INTO public.organization_icp_linkedin_urls (organization_id, url, url_type)
          VALUES (org_record.organization_id, linkedin_url, 'ideal_person')
          ON CONFLICT (organization_id, url, url_type) DO NOTHING;
        END LOOP;
      END IF;

      -- Exclusion list
      IF org_record.icp_settings->'exclusion_list' IS NOT NULL AND jsonb_typeof(org_record.icp_settings->'exclusion_list') = 'array' THEN
        FOR linkedin_url IN 
          SELECT jsonb_array_elements_text(org_record.icp_settings->'exclusion_list')
        LOOP
          INSERT INTO public.organization_icp_linkedin_urls (organization_id, url, url_type)
          VALUES (org_record.organization_id, linkedin_url, 'exclusion')
          ON CONFLICT (organization_id, url, url_type) DO NOTHING;
        END LOOP;
      END IF;

    END LOOP;
  END IF;
END $$;

-- Add indexes for array columns for better performance
CREATE INDEX IF NOT EXISTS idx_organization_settings_icp_industries ON public.organization_settings USING GIN (icp_industries);
CREATE INDEX IF NOT EXISTS idx_organization_settings_icp_job_titles ON public.organization_settings USING GIN (icp_job_titles);
CREATE INDEX IF NOT EXISTS idx_organization_settings_icp_regions ON public.organization_settings USING GIN (icp_primary_regions);

-- Drop the old JSONB column after verifying migration
ALTER TABLE public.organization_settings DROP COLUMN IF EXISTS icp_settings;

-- Add comments for documentation
COMMENT ON COLUMN public.organization_settings.icp_min_employees IS 'Minimum number of employees for target companies';
COMMENT ON COLUMN public.organization_settings.icp_max_employees IS 'Maximum number of employees for target companies';
COMMENT ON COLUMN public.organization_settings.icp_sales_process IS 'Sales process characteristics (e.g., high-ticket, complex sales)';
COMMENT ON COLUMN public.organization_settings.icp_industries IS 'Target industries';
COMMENT ON COLUMN public.organization_settings.icp_job_titles IS 'Preferred job titles of prospects';
COMMENT ON COLUMN public.organization_settings.icp_primary_regions IS 'Primary geographic regions to target';
COMMENT ON COLUMN public.organization_settings.icp_secondary_regions IS 'Secondary geographic regions to target';
COMMENT ON COLUMN public.organization_settings.icp_focus_areas IS 'Specific focus areas or niches';
COMMENT ON COLUMN public.organization_settings.icp_pain_points IS 'Common pain points of target prospects';

COMMENT ON TABLE public.organization_icp_linkedin_urls IS 'LinkedIn URLs for ICP settings (customers, ideal profiles, exclusions)';
COMMENT ON COLUMN public.organization_icp_linkedin_urls.url_type IS 'Type of LinkedIn URL: current_customer, ideal_customer, ideal_person, or exclusion'; 