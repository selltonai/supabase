-- Add location targeting columns to campaigns table
ALTER TABLE campaigns 
ADD COLUMN IF NOT EXISTS icp_country text,
ADD COLUMN IF NOT EXISTS icp_city text,
ADD COLUMN IF NOT EXISTS location_type text DEFAULT 'region_based' CHECK (location_type IN ('region_based', 'city_based'));

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_campaigns_location_type ON campaigns(location_type);
CREATE INDEX IF NOT EXISTS idx_campaigns_icp_country ON campaigns(icp_country);
CREATE INDEX IF NOT EXISTS idx_campaigns_icp_city ON campaigns(icp_city);

-- Add comment
COMMENT ON COLUMN campaigns.location_type IS 'Location targeting type: region_based or city_based';
COMMENT ON COLUMN campaigns.icp_country IS 'Country for city-based location targeting';
COMMENT ON COLUMN campaigns.icp_city IS 'City for city-based location targeting';
