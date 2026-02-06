-- Migration: Campaign Metrics Functions
-- Description: Creates functions and triggers to automatically update campaign metrics
-- Author: System
-- Date: 2025-01-30

-- Function to increment emails_sent counter
CREATE OR REPLACE FUNCTION increment_campaign_emails_sent(campaign_id UUID)
RETURNS void AS $$
BEGIN
  UPDATE campaigns 
  SET emails_sent = emails_sent + 1,
      updated_at = NOW()
  WHERE id = campaign_id;
END;
$$ LANGUAGE plpgsql;

-- Function to increment emails_delivered counter
CREATE OR REPLACE FUNCTION increment_campaign_emails_delivered(campaign_id UUID)
RETURNS void AS $$
BEGIN
  UPDATE campaigns 
  SET emails_delivered = emails_delivered + 1,
      updated_at = NOW()
  WHERE id = campaign_id;
END;
$$ LANGUAGE plpgsql;

-- Function to increment emails_opened counter
CREATE OR REPLACE FUNCTION increment_campaign_emails_opened(campaign_id UUID)
RETURNS void AS $$
BEGIN
  UPDATE campaigns 
  SET emails_opened = emails_opened + 1,
      updated_at = NOW()
  WHERE id = campaign_id;
END;
$$ LANGUAGE plpgsql;

-- Function to increment emails_replied counter
CREATE OR REPLACE FUNCTION increment_campaign_emails_replied(campaign_id UUID)
RETURNS void AS $$
BEGIN
  UPDATE campaigns 
  SET emails_replied = emails_replied + 1,
      updated_at = NOW()
  WHERE id = campaign_id;
END;
$$ LANGUAGE plpgsql;

-- Function to increment emails_bounced counter
CREATE OR REPLACE FUNCTION increment_campaign_emails_bounced(campaign_id UUID)
RETURNS void AS $$
BEGIN
  UPDATE campaigns 
  SET emails_bounced = emails_bounced + 1,
      updated_at = NOW()
  WHERE id = campaign_id;
END;
$$ LANGUAGE plpgsql;

-- Function to increment meetings_booked counter
CREATE OR REPLACE FUNCTION increment_campaign_meetings_booked(campaign_id UUID)
RETURNS void AS $$
BEGIN
  UPDATE campaigns 
  SET meetings_booked = meetings_booked + 1,
      updated_at = NOW()
  WHERE id = campaign_id;
END;
$$ LANGUAGE plpgsql;

-- Function to automatically update campaign metrics when email status changes
CREATE OR REPLACE FUNCTION update_campaign_metrics()
RETURNS trigger AS $$
BEGIN
  -- Only process if status actually changed
  IF TG_OP = 'UPDATE' AND OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;

  -- Handle status changes
  CASE NEW.status
    WHEN 'sent' THEN
      -- Only increment if transitioning from a non-sent status
      IF TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND OLD.status != 'sent') THEN
        PERFORM increment_campaign_emails_sent(NEW.campaign_id);
      END IF;
      
    WHEN 'delivered' THEN
      -- Only increment if transitioning from a non-delivered status
      IF TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND OLD.status NOT IN ('delivered', 'opened', 'replied')) THEN
        PERFORM increment_campaign_emails_delivered(NEW.campaign_id);
      END IF;
      
    WHEN 'opened' THEN
      -- Only increment if transitioning from a non-opened status
      IF TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND OLD.status NOT IN ('opened', 'replied')) THEN
        -- Also increment delivered if not already done
        IF TG_OP = 'UPDATE' AND OLD.status NOT IN ('delivered', 'opened', 'replied') THEN
          PERFORM increment_campaign_emails_delivered(NEW.campaign_id);
        END IF;
        PERFORM increment_campaign_emails_opened(NEW.campaign_id);
      END IF;
      
    WHEN 'replied' THEN
      -- Only increment if transitioning from a non-replied status
      IF TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND OLD.status != 'replied') THEN
        -- Also increment delivered and opened if not already done
        IF TG_OP = 'UPDATE' AND OLD.status NOT IN ('delivered', 'opened', 'replied') THEN
          PERFORM increment_campaign_emails_delivered(NEW.campaign_id);
        END IF;
        IF TG_OP = 'UPDATE' AND OLD.status NOT IN ('opened', 'replied') THEN
          PERFORM increment_campaign_emails_opened(NEW.campaign_id);
        END IF;
        PERFORM increment_campaign_emails_replied(NEW.campaign_id);
      END IF;
      
    WHEN 'bounced' THEN
      -- Only increment if transitioning from a non-bounced status
      IF TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND OLD.status != 'bounced') THEN
        PERFORM increment_campaign_emails_bounced(NEW.campaign_id);
      END IF;
      
    ELSE
      -- No action for other statuses (draft, scheduled, failed)
      NULL;
  END CASE;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to automatically update campaign metrics
DROP TRIGGER IF EXISTS trigger_update_campaign_metrics ON campaign_emails;
CREATE TRIGGER trigger_update_campaign_metrics
  AFTER INSERT OR UPDATE OF status ON campaign_emails
  FOR EACH ROW
  EXECUTE FUNCTION update_campaign_metrics();

-- Function to create contact activity when email status changes
CREATE OR REPLACE FUNCTION create_email_status_activity()
RETURNS trigger AS $$
DECLARE
  activity_title TEXT;
  activity_description TEXT;
  activity_type_name activity_type;
BEGIN
  -- Only create activities for certain status changes
  IF TG_OP = 'UPDATE' AND OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;

  -- Determine activity type and title based on new status
  CASE NEW.status
    WHEN 'sent' THEN
      activity_type_name := 'email_sent';
      activity_title := 'Campaign email sent';
      activity_description := COALESCE('Email "' || NEW.subject || '" sent successfully', 'Campaign email sent');
      
    WHEN 'delivered' THEN
      activity_type_name := 'email_sent'; -- We'll use email_sent type for delivered
      activity_title := 'Email delivered';
      activity_description := COALESCE('Email "' || NEW.subject || '" was delivered', 'Campaign email delivered');
      
    WHEN 'opened' THEN
      activity_type_name := 'email_sent'; -- We'll use email_sent type for opened
      activity_title := 'Email opened';
      activity_description := COALESCE('Email "' || NEW.subject || '" was opened by recipient', 'Campaign email opened');
      
    WHEN 'replied' THEN
      activity_type_name := 'email_received';
      activity_title := 'Received reply to campaign email';
      activity_description := COALESCE('Reply received for email "' || NEW.subject || '"', 'Reply received to campaign email');
      
    WHEN 'bounced' THEN
      activity_type_name := 'email_sent';
      activity_title := 'Email bounced';
      activity_description := COALESCE('Email "' || NEW.subject || '" bounced', 'Campaign email bounced');
      
    ELSE
      -- No activity for draft, scheduled, failed
      RETURN NEW;
  END CASE;

  -- Insert the activity record
  INSERT INTO contact_activities (
    contact_id,
    organization_id,
    activity_type,
    title,
    description,
    metadata,
    occurred_at
  ) VALUES (
    NEW.contact_id,
    NEW.organization_id,
    activity_type_name,
    activity_title,
    activity_description,
    jsonb_build_object(
      'campaign_email_id', NEW.id,
      'campaign_id', NEW.campaign_id,
      'email_status', NEW.status,
      'subject', NEW.subject,
      'message_id', NEW.message_id,
      'thread_id', NEW.thread_id
    ),
    CASE NEW.status
      WHEN 'sent' THEN NEW.sent_at
      WHEN 'delivered' THEN NEW.delivered_at
      WHEN 'opened' THEN NEW.opened_at
      WHEN 'replied' THEN NEW.replied_at
      WHEN 'bounced' THEN NEW.bounced_at
      ELSE NOW()
    END
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to automatically create contact activities
DROP TRIGGER IF EXISTS trigger_create_email_status_activity ON campaign_emails;
CREATE TRIGGER trigger_create_email_status_activity
  AFTER INSERT OR UPDATE OF status ON campaign_emails
  FOR EACH ROW
  EXECUTE FUNCTION create_email_status_activity();

-- Add indexes for better performance on campaign metrics queries
CREATE INDEX IF NOT EXISTS idx_campaign_emails_status_campaign_id ON campaign_emails(status, campaign_id);
CREATE INDEX IF NOT EXISTS idx_campaign_emails_sent_at ON campaign_emails(sent_at) WHERE sent_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_campaign_emails_opened_at ON campaign_emails(opened_at) WHERE opened_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_campaign_emails_replied_at ON campaign_emails(replied_at) WHERE replied_at IS NOT NULL;

COMMENT ON FUNCTION increment_campaign_emails_sent IS 'Increments the emails_sent counter for a campaign';
COMMENT ON FUNCTION increment_campaign_emails_delivered IS 'Increments the emails_delivered counter for a campaign';
COMMENT ON FUNCTION increment_campaign_emails_opened IS 'Increments the emails_opened counter for a campaign';
COMMENT ON FUNCTION increment_campaign_emails_replied IS 'Increments the emails_replied counter for a campaign';
COMMENT ON FUNCTION increment_campaign_emails_bounced IS 'Increments the emails_bounced counter for a campaign';
COMMENT ON FUNCTION update_campaign_metrics IS 'Automatically updates campaign metrics when email status changes';
COMMENT ON FUNCTION create_email_status_activity IS 'Automatically creates contact activities when email status changes'; 