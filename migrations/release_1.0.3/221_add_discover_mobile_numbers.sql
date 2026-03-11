-- Add discover_mobile_numbers column to campaigns table
-- This field controls whether phone discovery is enabled for the campaign

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'campaigns') THEN
        ALTER TABLE campaigns ADD COLUMN IF NOT EXISTS discover_mobile_numbers BOOLEAN DEFAULT FALSE;
    END IF;
END $$;

-- Add index for performance
CREATE INDEX IF NOT EXISTS idx_campaigns_discover_mobile_numbers ON campaigns(discover_mobile_numbers);

-- Add comment for documentation
COMMENT ON COLUMN campaigns.discover_mobile_numbers IS 'Whether to discover mobile phone numbers for contacts in this campaign (default: false)';
