-- Migration: Add Campaign Contact Relationship and Constraints
-- Description: Ensures proper relationships between campaigns, contacts, and related tables
-- Author: System
-- Date: 2025-01-30

-- Add campaign_id to contacts table if it doesn't exist
ALTER TABLE contacts ADD COLUMN IF NOT EXISTS campaign_id UUID REFERENCES campaigns(id) ON DELETE SET NULL;

-- Create index on campaign_id in contacts table
CREATE INDEX IF NOT EXISTS idx_contacts_campaign_id ON contacts(campaign_id);

-- Add constraint to ensure campaign_emails references valid contacts and campaigns
ALTER TABLE campaign_emails DROP CONSTRAINT IF EXISTS campaign_emails_valid_refs;
ALTER TABLE campaign_emails ADD CONSTRAINT campaign_emails_valid_refs 
  CHECK (campaign_id IS NOT NULL AND contact_id IS NOT NULL);

-- Add constraint to ensure tasks have proper relationships
ALTER TABLE tasks DROP CONSTRAINT IF EXISTS tasks_valid_type_refs;
ALTER TABLE tasks ADD CONSTRAINT tasks_valid_type_refs 
  CHECK (
    CASE 
      WHEN task_type = 'review_draft' THEN campaign_id IS NOT NULL
      WHEN task_type = 'send_email' THEN campaign_id IS NOT NULL AND contact_id IS NOT NULL
      WHEN task_type = 'follow_up' THEN contact_id IS NOT NULL
      WHEN task_type = 'meeting' THEN contact_id IS NOT NULL
      ELSE TRUE
    END
  );

-- Create function to update campaign metrics when email status changes
CREATE OR REPLACE FUNCTION update_campaign_metrics()
RETURNS TRIGGER AS $$
BEGIN
  -- Update campaign metrics based on email status changes
  IF NEW.status = 'sent' AND (OLD.status IS NULL OR OLD.status != 'sent') THEN
    UPDATE campaigns 
    SET emails_sent = emails_sent + 1 
    WHERE id = NEW.campaign_id;
  END IF;
  
  IF NEW.status = 'delivered' AND (OLD.status IS NULL OR OLD.status != 'delivered') THEN
    UPDATE campaigns 
    SET emails_delivered = emails_delivered + 1 
    WHERE id = NEW.campaign_id;
  END IF;
  
  IF NEW.opened_at IS NOT NULL AND OLD.opened_at IS NULL THEN
    UPDATE campaigns 
    SET emails_opened = emails_opened + 1 
    WHERE id = NEW.campaign_id;
  END IF;
  
  IF NEW.clicked_at IS NOT NULL AND OLD.clicked_at IS NULL THEN
    UPDATE campaigns 
    SET emails_clicked = emails_clicked + 1 
    WHERE id = NEW.campaign_id;
  END IF;
  
  IF NEW.replied_at IS NOT NULL AND OLD.replied_at IS NULL THEN
    UPDATE campaigns 
    SET emails_replied = emails_replied + 1 
    WHERE id = NEW.campaign_id;
  END IF;
  
  IF NEW.status = 'bounced' AND (OLD.status IS NULL OR OLD.status != 'bounced') THEN
    UPDATE campaigns 
    SET emails_bounced = emails_bounced + 1 
    WHERE id = NEW.campaign_id;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for updating campaign metrics
DROP TRIGGER IF EXISTS update_campaign_metrics_trigger ON campaign_emails;
CREATE TRIGGER update_campaign_metrics_trigger
  AFTER INSERT OR UPDATE ON campaign_emails
  FOR EACH ROW
  EXECUTE FUNCTION update_campaign_metrics();

-- Create function to handle meeting bookings
CREATE OR REPLACE FUNCTION handle_meeting_booking()
RETURNS TRIGGER AS $$
BEGIN
  -- When a meeting is booked, update the campaign metrics
  IF NEW.activity_type = 'meeting_booked' THEN
    UPDATE campaigns 
    SET meetings_booked = meetings_booked + 1 
    WHERE id = NEW.campaign_id;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for meeting bookings
DROP TRIGGER IF EXISTS handle_meeting_booking_trigger ON campaign_activities;
CREATE TRIGGER handle_meeting_booking_trigger
  AFTER INSERT ON campaign_activities
  FOR EACH ROW
  EXECUTE FUNCTION handle_meeting_booking();

-- Add function to get campaign summary
CREATE OR REPLACE FUNCTION get_campaign_summary(p_campaign_id UUID)
RETURNS TABLE (
  total_contacts INTEGER,
  emails_sent INTEGER,
  emails_delivered INTEGER,
  emails_opened INTEGER,
  emails_replied INTEGER,
  meetings_booked INTEGER,
  open_rate NUMERIC,
  reply_rate NUMERIC,
  meeting_rate NUMERIC
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    c.total_contacts,
    c.emails_sent,
    c.emails_delivered,
    c.emails_opened,
    c.emails_replied,
    c.meetings_booked,
    CASE 
      WHEN c.emails_sent > 0 THEN ROUND((c.emails_opened::NUMERIC / c.emails_sent) * 100, 2)
      ELSE 0
    END as open_rate,
    CASE 
      WHEN c.emails_sent > 0 THEN ROUND((c.emails_replied::NUMERIC / c.emails_sent) * 100, 2)
      ELSE 0
    END as reply_rate,
    CASE 
      WHEN c.emails_sent > 0 THEN ROUND((c.meetings_booked::NUMERIC / c.emails_sent) * 100, 2)
      ELSE 0
    END as meeting_rate
  FROM campaigns c
  WHERE c.id = p_campaign_id;
END;
$$ LANGUAGE plpgsql;

-- Add comments
COMMENT ON FUNCTION update_campaign_metrics() IS 'Automatically updates campaign metrics when email status changes';
COMMENT ON FUNCTION handle_meeting_booking() IS 'Updates campaign meeting count when a meeting is booked';
COMMENT ON FUNCTION get_campaign_summary(UUID) IS 'Returns summary metrics for a specific campaign'; 