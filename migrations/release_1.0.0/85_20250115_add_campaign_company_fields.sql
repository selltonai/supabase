-- Migration: Add Company Fields to Campaigns Table
-- Description: Adds dedicated fields to store company/lead data and curated selections
-- Author: System
-- Date: 2025-01-15

-- Add dedicated fields for storing company/lead data in campaigns
ALTER TABLE campaigns 
  -- Lead source and processing
  ADD COLUMN IF NOT EXISTS lead_source TEXT, -- 'csv', 'manual', 'ai_generated'
  ADD COLUMN IF NOT EXISTS product_description TEXT, -- Product/service description for the campaign
  
  -- B2B results for manual input
  ADD COLUMN IF NOT EXISTS b2b_results JSONB, -- Results from B2B API for manual LinkedIn URLs
  
  -- CSV results and processing
  ADD COLUMN IF NOT EXISTS csv_results JSONB, -- CSV processing results and analysis
  
  -- Curated company selections (the main focus of this migration)
  ADD COLUMN IF NOT EXISTS curated_companies JSONB, -- Array of curated company data with selection status
  ADD COLUMN IF NOT EXISTS selected_company_ids TEXT[] DEFAULT '{}', -- Array of selected company IDs for quick filtering
  
  -- Wizard completion tracking
  ADD COLUMN IF NOT EXISTS wizard_completed BOOLEAN DEFAULT FALSE, -- Whether the campaign wizard was completed
  
  -- Processing metadata
  ADD COLUMN IF NOT EXISTS processing_status TEXT DEFAULT 'pending', -- pending, processing, completed, failed
  ADD COLUMN IF NOT EXISTS processing_started_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS processing_completed_at TIMESTAMPTZ;

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_campaigns_lead_source ON campaigns(lead_source);
CREATE INDEX IF NOT EXISTS idx_campaigns_selected_company_ids ON campaigns USING GIN (selected_company_ids);
CREATE INDEX IF NOT EXISTS idx_campaigns_wizard_completed ON campaigns(wizard_completed);
CREATE INDEX IF NOT EXISTS idx_campaigns_processing_status ON campaigns(processing_status);

-- Create GIN indexes for JSONB columns
CREATE INDEX IF NOT EXISTS idx_campaigns_b2b_results ON campaigns USING GIN (b2b_results);
CREATE INDEX IF NOT EXISTS idx_campaigns_csv_results ON campaigns USING GIN (csv_results);
CREATE INDEX IF NOT EXISTS idx_campaigns_curated_companies ON campaigns USING GIN (curated_companies);

-- Add comments for documentation
COMMENT ON COLUMN campaigns.lead_source IS 'Source of leads/companies: csv, manual, ai_generated';
COMMENT ON COLUMN campaigns.product_description IS 'Description of product/service for this campaign';
COMMENT ON COLUMN campaigns.b2b_results IS 'Results from B2B enrichment API for manual LinkedIn URL input';
COMMENT ON COLUMN campaigns.csv_results IS 'Results from CSV processing including file info, column mapping, and analysis';
COMMENT ON COLUMN campaigns.curated_companies IS 'Array of company data with selection status and curation info';
COMMENT ON COLUMN campaigns.selected_company_ids IS 'Array of selected company IDs for quick filtering and queries';
COMMENT ON COLUMN campaigns.wizard_completed IS 'Whether the campaign creation wizard was completed';
COMMENT ON COLUMN campaigns.processing_status IS 'Status of campaign processing (pending, processing, completed, failed)';
COMMENT ON COLUMN campaigns.processing_started_at IS 'When campaign processing started';
COMMENT ON COLUMN campaigns.processing_completed_at IS 'When campaign processing completed';

-- Create function to update selected_company_ids from curated_companies
CREATE OR REPLACE FUNCTION update_selected_company_ids()
RETURNS TRIGGER AS $$
BEGIN
    -- Extract selected company IDs from curated_companies JSONB
    IF NEW.curated_companies IS NOT NULL THEN
        NEW.selected_company_ids := ARRAY(
            SELECT jsonb_array_elements_text(
                jsonb_path_query_array(NEW.curated_companies, '$[*] ? (@.selected == true).id')
            )
        );
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to automatically update selected_company_ids when curated_companies changes
DROP TRIGGER IF EXISTS trigger_update_selected_company_ids ON campaigns;
CREATE TRIGGER trigger_update_selected_company_ids
    BEFORE INSERT OR UPDATE OF curated_companies ON campaigns
    FOR EACH ROW
    EXECUTE FUNCTION update_selected_company_ids();

-- Migrate existing data from metadata to new columns
DO $$
DECLARE
  campaign_record RECORD;
  metadata_data JSONB;
  external_companies JSONB;
  selected_companies JSONB;
  curated_data JSONB;
BEGIN
  -- Loop through all campaigns that have metadata
  FOR campaign_record IN 
    SELECT id, metadata
    FROM campaigns
    WHERE metadata IS NOT NULL
  LOOP
    metadata_data := campaign_record.metadata;
    
    -- Extract and migrate lead source
    IF metadata_data->>'lead_source' IS NOT NULL OR metadata_data->>'company_source' IS NOT NULL THEN
      UPDATE campaigns
      SET lead_source = COALESCE(metadata_data->>'lead_source', metadata_data->>'company_source')
      WHERE id = campaign_record.id;
    END IF;
    
    -- Extract and migrate product description
    IF metadata_data->>'product_service_description' IS NOT NULL THEN
      UPDATE campaigns
      SET product_description = metadata_data->>'product_service_description'
      WHERE id = campaign_record.id;
    END IF;
    
    -- Extract and migrate CSV results
    IF metadata_data->'csv_analysis' IS NOT NULL OR metadata_data->>'csv_file_name' IS NOT NULL THEN
      UPDATE campaigns
      SET csv_results = jsonb_build_object(
        'file_name', metadata_data->>'csv_file_name',
        'analysis', metadata_data->'csv_analysis',
        'column_mapping', metadata_data->'csv_column_mapping',
        'uploaded_at', metadata_data->>'last_updated'
      )
      WHERE id = campaign_record.id;
    END IF;
    
    -- Extract and migrate wizard completion status
    IF metadata_data->'completed_steps' IS NOT NULL THEN
      UPDATE campaigns
      SET wizard_completed = (
        jsonb_array_length(metadata_data->'completed_steps') >= 5 OR
        (metadata_data->'completed_steps' @> '["review-launch"]'::jsonb)
      )
      WHERE id = campaign_record.id;
    END IF;
    
    -- Extract and migrate curated companies
    external_companies := metadata_data->'external_companies';
    selected_companies := metadata_data->'selected_companies';
    
    IF external_companies IS NOT NULL OR selected_companies IS NOT NULL THEN
      -- Use external_companies if available, otherwise use selected_companies
      curated_data := COALESCE(external_companies, selected_companies);
      
      -- Add selection status to each company (assume all are selected if in the list)
      curated_data := (
        SELECT jsonb_agg(
          company_item || jsonb_build_object('selected', true)
        )
        FROM jsonb_array_elements(curated_data) AS company_item
      );
      
      UPDATE campaigns
      SET curated_companies = curated_data
      WHERE id = campaign_record.id;
    END IF;
  END LOOP;
END $$; 