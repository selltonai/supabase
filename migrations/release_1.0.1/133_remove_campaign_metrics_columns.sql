-- Migration: Remove campaign metrics and unused columns from campaigns table
-- Created: 2025-10-31
-- Purpose: Remove redundant metrics columns that are calculated from campaign_emails and campaign_companies tables,
--          and remove unused columns that have been moved to metadata
-- Description: Removes:
--              - Metrics columns: total_contacts, emails_sent, emails_delivered, emails_opened, emails_clicked, 
--                emails_replied, emails_bounced, meetings_booked
--              - Unused contact metrics: contacts_reached, contacts_replied
--              - Moved to metadata: current_step, completed_steps (now stored in metadata JSONB)
--              - Unused processing fields: processing_status, processing_started_at, processing_completed_at
--              These metrics should be calculated dynamically from campaign_emails and campaign_companies tables.
--              Note: Safely handles cases where campaign_contacts table may not exist.

-- ============================================================================
-- STEP 1: Drop triggers that update these metrics
-- ============================================================================

-- Drop trigger for campaign metrics updates
DROP TRIGGER IF EXISTS trigger_update_campaign_metrics ON campaign_emails;
DROP TRIGGER IF EXISTS update_campaign_metrics_trigger ON campaign_emails;

-- Drop trigger for campaign contact count updates (only if campaign_contacts table exists)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'campaign_contacts') THEN
        DROP TRIGGER IF EXISTS trigger_update_campaign_contact_count ON campaign_contacts;
        DROP TRIGGER IF EXISTS trigger_update_campaign_total_contacts ON campaign_contacts;
    END IF;
END $$;

-- Drop trigger for meeting bookings
DROP TRIGGER IF EXISTS handle_meeting_booking_trigger ON campaign_activities;

-- Drop triggers for contact metrics
DROP TRIGGER IF EXISTS update_contacts_reached_trigger ON campaign_emails;
DROP TRIGGER IF EXISTS update_contacts_replied_trigger ON campaign_emails;

-- ============================================================================
-- STEP 2: Drop functions that update these metrics
-- ============================================================================

-- Drop increment functions for email metrics
DROP FUNCTION IF EXISTS increment_campaign_emails_sent(UUID);
DROP FUNCTION IF EXISTS increment_campaign_emails_delivered(UUID);
DROP FUNCTION IF EXISTS increment_campaign_emails_opened(UUID);
DROP FUNCTION IF EXISTS increment_campaign_emails_replied(UUID);
DROP FUNCTION IF EXISTS increment_campaign_emails_bounced(UUID);
DROP FUNCTION IF EXISTS increment_campaign_meetings_booked(UUID);

-- Drop main update functions
DROP FUNCTION IF EXISTS update_campaign_metrics();
-- Drop contact count functions only if they exist (campaign_contacts table may not exist)
DROP FUNCTION IF EXISTS update_campaign_contact_count();
DROP FUNCTION IF EXISTS update_campaign_total_contacts();

-- Drop meeting booking handler
DROP FUNCTION IF EXISTS handle_meeting_booking();

-- Drop contact metrics functions
DROP FUNCTION IF EXISTS update_contacts_reached();
DROP FUNCTION IF EXISTS update_contacts_replied();

-- Drop step tracking function (if exists, as steps are now in metadata)
DROP FUNCTION IF EXISTS update_campaign_step(UUID, INTEGER, TEXT[]);

-- ============================================================================
-- STEP 3: Drop indexes related to these columns (if they exist)
-- ============================================================================

-- Drop indexes for removed columns
DROP INDEX IF EXISTS idx_campaigns_total_contacts;
DROP INDEX IF EXISTS idx_campaigns_current_step;
DROP INDEX IF EXISTS idx_campaigns_processing_status;

-- Drop check constraints for these columns
ALTER TABLE campaigns DROP CONSTRAINT IF EXISTS campaigns_total_contacts_check;
ALTER TABLE campaigns DROP CONSTRAINT IF EXISTS campaigns_emails_sent_check;
ALTER TABLE campaigns DROP CONSTRAINT IF EXISTS campaigns_emails_delivered_check;
ALTER TABLE campaigns DROP CONSTRAINT IF EXISTS campaigns_emails_opened_check;
ALTER TABLE campaigns DROP CONSTRAINT IF EXISTS campaigns_emails_clicked_check;
ALTER TABLE campaigns DROP CONSTRAINT IF EXISTS campaigns_emails_replied_check;
ALTER TABLE campaigns DROP CONSTRAINT IF EXISTS campaigns_emails_bounced_check;
ALTER TABLE campaigns DROP CONSTRAINT IF EXISTS campaigns_meetings_booked_check;
ALTER TABLE campaigns DROP CONSTRAINT IF EXISTS campaigns_contacts_reached_check;
ALTER TABLE campaigns DROP CONSTRAINT IF EXISTS campaigns_contacts_replied_check;

-- ============================================================================
-- STEP 4: Drop columns from campaigns table
-- ============================================================================

-- Drop metrics columns
ALTER TABLE campaigns DROP COLUMN IF EXISTS total_contacts;
ALTER TABLE campaigns DROP COLUMN IF EXISTS emails_sent;
ALTER TABLE campaigns DROP COLUMN IF EXISTS emails_delivered;
ALTER TABLE campaigns DROP COLUMN IF EXISTS emails_opened;
ALTER TABLE campaigns DROP COLUMN IF EXISTS emails_clicked;
ALTER TABLE campaigns DROP COLUMN IF EXISTS emails_replied;
ALTER TABLE campaigns DROP COLUMN IF EXISTS emails_bounced;
ALTER TABLE campaigns DROP COLUMN IF EXISTS meetings_booked;

-- Drop unused contact metrics columns
ALTER TABLE campaigns DROP COLUMN IF EXISTS contacts_reached;
ALTER TABLE campaigns DROP COLUMN IF EXISTS contacts_replied;

-- Drop step tracking columns (moved to metadata)
ALTER TABLE campaigns DROP COLUMN IF EXISTS current_step;
ALTER TABLE campaigns DROP COLUMN IF EXISTS completed_steps;

-- Drop unused processing fields
ALTER TABLE campaigns DROP COLUMN IF EXISTS processing_status;
ALTER TABLE campaigns DROP COLUMN IF EXISTS processing_started_at;
ALTER TABLE campaigns DROP COLUMN IF EXISTS processing_completed_at;

-- ============================================================================
-- STEP 5: Log the cleanup
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE 'Successfully removed campaign metrics and unused columns from campaigns table';
    RAISE NOTICE 'Removed metrics columns: total_contacts, emails_sent, emails_delivered, emails_opened, emails_clicked, emails_replied, emails_bounced, meetings_booked';
    RAISE NOTICE 'Removed unused columns: contacts_reached, contacts_replied';
    RAISE NOTICE 'Removed step tracking columns (moved to metadata): current_step, completed_steps';
    RAISE NOTICE 'Removed unused processing fields: processing_status, processing_started_at, processing_completed_at';
    RAISE NOTICE 'Removed all associated triggers and functions';
    RAISE NOTICE 'Metrics should now be calculated dynamically from campaign_emails and campaign_companies tables';
    RAISE NOTICE 'Step tracking is now stored in metadata.current_step and metadata.completed_steps';
END $$;

