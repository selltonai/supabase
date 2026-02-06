-- Migration: Cleanup Campaign Fields
-- Description: Clean up campaign fields to ensure consistency and remove any orphaned data
-- Author: System
-- Date: 2025-02-07

-- 1. Ensure wizard_completed is properly set for existing campaigns
UPDATE campaigns 
SET wizard_completed = TRUE 
WHERE status IN ('active', 'paused', 'completed', 'cancelled')
  AND (wizard_completed IS NULL OR wizard_completed = FALSE);

-- 2. Set wizard_completed for draft campaigns that have all steps completed
UPDATE campaigns 
SET wizard_completed = TRUE 
WHERE status = 'draft'
  AND wizard_completed = FALSE
  AND metadata->>'completed_steps' IS NOT NULL
  AND jsonb_array_length(metadata->'completed_steps') >= 5
  AND metadata->'completed_steps' @> '["campaign-details", "icp-settings", "lead-source", "curate-leads", "review-launch"]'::jsonb;

-- 3. Clean up any campaigns with inconsistent status/timestamp combinations
-- Set started_at for active campaigns that don't have it
UPDATE campaigns 
SET started_at = COALESCE(
  (metadata->>'launched_at')::timestamptz,
  created_at
)
WHERE status IN ('active', 'paused', 'completed')
  AND started_at IS NULL;

-- 4. Remove any launched_at from metadata since we use started_at in the main table
UPDATE campaigns 
SET metadata = metadata - 'launched_at'
WHERE metadata ? 'launched_at';

-- 5. Clean up any orphaned campaign data
-- Remove campaigns that have no organization (shouldn't happen but just in case)
DELETE FROM campaigns 
WHERE organization_id NOT IN (SELECT id FROM organization);

-- 6. Clean up campaign_emails for campaigns that don't exist
DELETE FROM campaign_emails 
WHERE campaign_id NOT IN (SELECT id FROM campaigns);

-- 7. Clean up campaign_activities for campaigns that don't exist
DELETE FROM campaign_activities 
WHERE campaign_id NOT IN (SELECT id FROM campaigns);

-- 8. Clean up tasks for campaigns that don't exist
UPDATE tasks 
SET campaign_id = NULL 
WHERE campaign_id IS NOT NULL 
  AND campaign_id NOT IN (SELECT id FROM campaigns);

-- 9. Ensure all campaigns have required default values
UPDATE campaigns 
SET 
  emails_sent = COALESCE(emails_sent, 0),
  emails_delivered = COALESCE(emails_delivered, 0),
  emails_opened = COALESCE(emails_opened, 0),
  emails_clicked = COALESCE(emails_clicked, 0),
  emails_replied = COALESCE(emails_replied, 0),
  emails_bounced = COALESCE(emails_bounced, 0),
  meetings_booked = COALESCE(meetings_booked, 0),
  total_contacts = COALESCE(total_contacts, 0),
  tags = COALESCE(tags, '{}'),
  metadata = COALESCE(metadata, '{}'),
  settings = COALESCE(settings, '{}'),
  target_audience = COALESCE(target_audience, '{}')
WHERE 
  emails_sent IS NULL OR
  emails_delivered IS NULL OR
  emails_opened IS NULL OR
  emails_clicked IS NULL OR
  emails_replied IS NULL OR
  emails_bounced IS NULL OR
  meetings_booked IS NULL OR
  total_contacts IS NULL OR
  tags IS NULL OR
  metadata IS NULL OR
  settings IS NULL OR
  target_audience IS NULL;

-- 10. Add any missing indexes for performance
CREATE INDEX IF NOT EXISTS idx_campaigns_wizard_completed ON campaigns(wizard_completed);
CREATE INDEX IF NOT EXISTS idx_campaigns_started_at ON campaigns(started_at);

-- 11. Update campaign statistics based on actual email data
UPDATE campaigns 
SET 
  emails_sent = COALESCE((
    SELECT COUNT(*) 
    FROM campaign_emails 
    WHERE campaign_id = campaigns.id 
      AND status IN ('sent', 'delivered', 'opened', 'clicked', 'replied')
  ), 0),
  emails_delivered = COALESCE((
    SELECT COUNT(*) 
    FROM campaign_emails 
    WHERE campaign_id = campaigns.id 
      AND status IN ('delivered', 'opened', 'clicked', 'replied')
  ), 0),
  emails_opened = COALESCE((
    SELECT COUNT(*) 
    FROM campaign_emails 
    WHERE campaign_id = campaigns.id 
      AND opened_at IS NOT NULL
  ), 0),
  emails_replied = COALESCE((
    SELECT COUNT(*) 
    FROM campaign_emails 
    WHERE campaign_id = campaigns.id 
      AND replied_at IS NOT NULL
  ), 0),
  meetings_booked = COALESCE((
    SELECT COUNT(*) 
    FROM campaign_activities 
    WHERE campaign_id = campaigns.id 
      AND activity_type = 'meeting_booked'
  ), 0)
WHERE id IN (
  SELECT DISTINCT campaign_id 
  FROM campaign_emails 
  WHERE campaign_id IS NOT NULL
);

-- Add comments for documentation
COMMENT ON COLUMN campaigns.wizard_completed IS 'Indicates whether the campaign creation wizard was fully completed. Required to be true before campaign can be started.';
COMMENT ON COLUMN campaigns.started_at IS 'Timestamp when the campaign was first activated/launched. Set when status changes from draft to active.';

-- Log the cleanup completion
INSERT INTO campaign_activities (
  campaign_id, 
  organization_id, 
  activity_type, 
  activity_data, 
  occurred_at
) 
SELECT 
  id,
  organization_id,
  'system_cleanup',
  jsonb_build_object(
    'cleanup_type', 'campaign_fields_cleanup',
    'migration', '71_20250207_cleanup_campaign_fields',
    'description', 'Cleaned up campaign fields and ensured data consistency'
  ),
  NOW()
FROM campaigns
WHERE wizard_completed = TRUE AND status IN ('active', 'paused', 'completed', 'cancelled'); 