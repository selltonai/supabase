-- Run this SQL script to add location targeting columns to the campaigns table
-- Execute this in your Supabase SQL editor or via psql

-- Add location targeting columns to campaigns table
ALTER TABLE campaigns 
ADD COLUMN IF NOT EXISTS icp_country text,
ADD COLUMN IF NOT EXISTS icp_city text,
ADD COLUMN IF NOT EXISTS location_type text DEFAULT 'region_based' CHECK (location_type IN ('region_based', 'city_based'));

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_campaigns_location_type ON campaigns(location_type);
CREATE INDEX IF NOT EXISTS idx_campaigns_icp_country ON campaigns(icp_country);
CREATE INDEX IF NOT EXISTS idx_campaigns_icp_city ON campaigns(icp_city);

-- Add comments for documentation
COMMENT ON COLUMN campaigns.location_type IS 'Location targeting type: region_based or city_based';
COMMENT ON COLUMN campaigns.icp_country IS 'Country for city-based location targeting';
COMMENT ON COLUMN campaigns.icp_city IS 'City for city-based location targeting';

-- Verify the columns were added
SELECT column_name, data_type, column_default 
FROM information_schema.columns 
WHERE table_name = 'campaigns' 
AND column_name IN ('icp_country', 'icp_city', 'location_type')
ORDER BY column_name;