-- Add contact-based reply tracking to campaigns table
ALTER TABLE campaigns 
ADD COLUMN IF NOT EXISTS contacts_reached INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS contacts_replied INTEGER DEFAULT 0;

-- Create a function to update contacts_reached when an email is sent
CREATE OR REPLACE FUNCTION update_contacts_reached()
RETURNS TRIGGER AS $$
BEGIN
    -- Only process if status changed to 'sent'
    IF NEW.status = 'sent' AND (OLD.status IS NULL OR OLD.status != 'sent') THEN
        -- Check if this contact has already been reached for this campaign
        IF NOT EXISTS (
            SELECT 1 FROM campaign_emails 
            WHERE campaign_id = NEW.campaign_id 
            AND contact_id = NEW.contact_id 
            AND status = 'sent'
            AND id != NEW.id
        ) THEN
            -- This is the first email sent to this contact for this campaign
            UPDATE campaigns 
            SET contacts_reached = contacts_reached + 1
            WHERE id = NEW.campaign_id;
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create a function to update contacts_replied when a reply is received
CREATE OR REPLACE FUNCTION update_contacts_replied()
RETURNS TRIGGER AS $$
BEGIN
    -- Only process if status changed to 'replied'
    IF NEW.status = 'replied' AND (OLD.status IS NULL OR OLD.status != 'replied') THEN
        -- Check if this contact has already replied to this campaign
        IF NOT EXISTS (
            SELECT 1 FROM campaign_emails 
            WHERE campaign_id = NEW.campaign_id 
            AND contact_id = NEW.contact_id 
            AND status = 'replied'
            AND id != NEW.id
        ) THEN
            -- This is the first reply from this contact for this campaign
            UPDATE campaigns 
            SET contacts_replied = contacts_replied + 1
            WHERE id = NEW.campaign_id;
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create triggers
DROP TRIGGER IF EXISTS update_contacts_reached_trigger ON campaign_emails;
CREATE TRIGGER update_contacts_reached_trigger
AFTER INSERT OR UPDATE ON campaign_emails
FOR EACH ROW
EXECUTE FUNCTION update_contacts_reached();

DROP TRIGGER IF EXISTS update_contacts_replied_trigger ON campaign_emails;
CREATE TRIGGER update_contacts_replied_trigger
AFTER INSERT OR UPDATE ON campaign_emails
FOR EACH ROW
EXECUTE FUNCTION update_contacts_replied();

-- Update existing data to populate the new columns
UPDATE campaigns c
SET contacts_reached = (
    SELECT COUNT(DISTINCT contact_id)
    FROM campaign_emails ce
    WHERE ce.campaign_id = c.id
    AND ce.status IN ('sent', 'delivered', 'opened', 'clicked', 'replied', 'bounced')
);

UPDATE campaigns c
SET contacts_replied = (
    SELECT COUNT(DISTINCT contact_id)
    FROM campaign_emails ce
    WHERE ce.campaign_id = c.id
    AND ce.status = 'replied'
);

-- Add comment to explain the fields
COMMENT ON COLUMN campaigns.contacts_reached IS 'Number of unique contacts who have received at least one email';
COMMENT ON COLUMN campaigns.contacts_replied IS 'Number of unique contacts who have sent at least one reply'; 