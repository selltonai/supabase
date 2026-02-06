-- Migration: Update Campaigns Fields
-- Description: Ensure total_contacts is saved properly and remove unnecessary scheduled date fields
-- Author: System
-- Date: 2025-01-10

-- Remove unnecessary scheduled date fields since we have launched_at and started_at
ALTER TABLE campaigns DROP COLUMN IF EXISTS scheduled_start_date;
ALTER TABLE campaigns DROP COLUMN IF EXISTS scheduled_end_date;

-- Ensure total_contacts field exists and has proper constraints
ALTER TABLE campaigns ADD COLUMN IF NOT EXISTS total_contacts INTEGER DEFAULT 0;

-- Add launched_at field if it doesn't exist (for tracking when campaign was launched)
ALTER TABLE campaigns ADD COLUMN IF NOT EXISTS launched_at TIMESTAMPTZ;

-- Add constraint to ensure total_contacts is not negative
ALTER TABLE campaigns DROP CONSTRAINT IF EXISTS campaigns_total_contacts_check;
ALTER TABLE campaigns ADD CONSTRAINT campaigns_total_contacts_check CHECK (total_contacts >= 0);

-- Create function to automatically update total_contacts when campaign_contacts change
CREATE OR REPLACE FUNCTION update_campaign_total_contacts()
RETURNS TRIGGER AS $$
BEGIN
    -- Update total_contacts for the affected campaign
    UPDATE campaigns 
    SET total_contacts = (
        SELECT COUNT(*) 
        FROM campaign_contacts 
        WHERE campaign_id = COALESCE(NEW.campaign_id, OLD.campaign_id)
        AND status = 'active'
    )
    WHERE id = COALESCE(NEW.campaign_id, OLD.campaign_id);
    
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- Create trigger to automatically update total_contacts
DROP TRIGGER IF EXISTS trigger_update_campaign_total_contacts ON campaign_contacts;
CREATE TRIGGER trigger_update_campaign_total_contacts
    AFTER INSERT OR UPDATE OR DELETE ON campaign_contacts
    FOR EACH ROW
    EXECUTE FUNCTION update_campaign_total_contacts();

-- Update existing campaigns to have correct total_contacts
UPDATE campaigns 
SET total_contacts = (
    SELECT COUNT(*) 
    FROM campaign_contacts 
    WHERE campaign_contacts.campaign_id = campaigns.id
    AND campaign_contacts.status = 'active'
)
WHERE id IN (
    SELECT DISTINCT campaign_id 
    FROM campaign_contacts
);

-- Add comments for documentation
COMMENT ON COLUMN campaigns.total_contacts IS 'Total number of active contacts in this campaign (automatically updated)';
COMMENT ON COLUMN campaigns.launched_at IS 'Timestamp when the campaign was launched/activated for the first time';
COMMENT ON COLUMN campaigns.started_at IS 'Timestamp when the campaign was started (may be same as launched_at or different for paused/resumed campaigns)';
COMMENT ON FUNCTION update_campaign_total_contacts IS 'Automatically updates total_contacts when campaign_contacts are added/removed/changed';

-- Add indexes for better performance
CREATE INDEX IF NOT EXISTS idx_campaigns_total_contacts ON campaigns(total_contacts);
CREATE INDEX IF NOT EXISTS idx_campaigns_launched_at ON campaigns(launched_at);
CREATE INDEX IF NOT EXISTS idx_campaigns_started_at ON campaigns(started_at); 