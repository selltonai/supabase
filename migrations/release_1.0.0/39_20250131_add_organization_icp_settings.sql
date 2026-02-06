-- Migration: Add organization ICP and settings columns
-- Purpose: Add support for ICP settings, API credentials, and company info
-- Date: 2025-01-31

-- Add ICP settings column
ALTER TABLE organization_settings 
ADD COLUMN IF NOT EXISTS icp_settings JSONB DEFAULT '{
    "ideal_clients": [],
    "current_customers": [],
    "exclusion_list": []
}'::jsonb;

-- Add API credentials column (encrypted storage)
ALTER TABLE organization_settings
ADD COLUMN IF NOT EXISTS api_credentials JSONB DEFAULT '{
    "cal_com_api_key": "",
    "calendly_api_key": ""
}'::jsonb;

-- Add company information column
ALTER TABLE organization_settings
ADD COLUMN IF NOT EXISTS company_info JSONB DEFAULT '{
    "website": "",
    "linkedin_profile": ""
}'::jsonb;

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_organization_settings_icp_settings ON organization_settings USING GIN (icp_settings);
CREATE INDEX IF NOT EXISTS idx_organization_settings_api_credentials ON organization_settings USING GIN (api_credentials);
CREATE INDEX IF NOT EXISTS idx_organization_settings_company_info ON organization_settings USING GIN (company_info);

-- Add column comments for documentation
COMMENT ON COLUMN organization_settings.icp_settings IS 'ICP (Ideal Customer Profile) settings including ideal clients, current customers, and exclusion lists';
COMMENT ON COLUMN organization_settings.api_credentials IS 'Encrypted API credentials for integrations like Cal.com and Calendly';
COMMENT ON COLUMN organization_settings.company_info IS 'Company information including website and LinkedIn profile'; 