-- Add ICP and API credentials settings to organization_settings table
-- This extends the existing organization_settings structure

ALTER TABLE organization_settings 
ADD COLUMN IF NOT EXISTS icp_settings JSONB DEFAULT '{
    "ideal_clients": [],
    "current_customers": [],
    "exclusion_list": []
}'::jsonb,
ADD COLUMN IF NOT EXISTS api_credentials JSONB DEFAULT '{
    "cal_com_api_key": "",
    "calendly_api_key": ""
}'::jsonb,
ADD COLUMN IF NOT EXISTS company_info JSONB DEFAULT '{
    "website": "",
    "linkedin_profile": ""
}'::jsonb;

-- Create indexes for better performance on JSONB queries
CREATE INDEX IF NOT EXISTS idx_organization_settings_icp_settings ON organization_settings USING GIN (icp_settings);
CREATE INDEX IF NOT EXISTS idx_organization_settings_api_credentials ON organization_settings USING GIN (api_credentials);
CREATE INDEX IF NOT EXISTS idx_organization_settings_company_info ON organization_settings USING GIN (company_info);

-- Add comments to document the new columns
COMMENT ON COLUMN organization_settings.icp_settings IS 'Ideal Customer Profile settings including ideal clients, current customers, and exclusion lists';
COMMENT ON COLUMN organization_settings.api_credentials IS 'API credentials for calendar integrations (Cal.com, Calendly)';
COMMENT ON COLUMN organization_settings.company_info IS 'Organization-level company information including website, name, and LinkedIn profile'; 