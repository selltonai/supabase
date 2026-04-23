-- Add phone_discovery_mode column to campaigns table
-- This field controls how phone discovery is applied: 'disabled', 'new_contacts_only', or 'all_contacts'

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'campaigns') THEN
        ALTER TABLE campaigns ADD COLUMN IF NOT EXISTS phone_discovery_mode VARCHAR(50) DEFAULT 'disabled';
    END IF;
END $$;

-- Add index for performance
CREATE INDEX IF NOT EXISTS idx_campaigns_phone_discovery_mode ON campaigns(phone_discovery_mode);

-- Add comment for documentation
COMMENT ON COLUMN campaigns.phone_discovery_mode IS 'Phone discovery mode: disabled, new_contacts_only (only for future discoveries), or all_contacts (for all contacts in campaign)';
