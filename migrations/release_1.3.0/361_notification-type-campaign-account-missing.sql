-- ============================================================
-- Migration: 361_notification-type-campaign-account-missing
-- Date:      2026-08-11
-- Purpose:   Allow the `linkedin_campaign_account_missing` notification type.
-- Projects:  selltonai-database/supabase (owner), selltonai (producer + UI).
-- Contract:  Extends the notification type CHECK with one new LinkedIn type.
--            Everything allowed by 353 stays allowed — same list plus one.
-- Depends:   353, which built the list under the temporary name
--            `notifications_type_check_crm_next`, dropped the previous
--            `notifications_type_check`, and then RENAMED the new one to
--            `notifications_type_check`. The LIVE constraint name is therefore
--            `notifications_type_check`; `_crm_next` should not exist.
--
-- Why name-robust: an earlier draft of this migration targeted `_crm_next`
-- only. That DROP would have been a silent no-op and the ADD would have left
-- the table carrying BOTH constraints — the old one still rejecting the new
-- type. The migration would have "applied successfully" and fixed nothing.
-- This version drops BOTH candidate names, so it is correct whether or not
-- 353's rename step completed on the target database.
--
-- Why the type: LinkedIn auto-enrol skips a campaign on every 5-minute tick
-- when no ACTIVE LinkedIn account resolves for the campaign owner, and said so
-- only in a server log. One production campaign sat dead for days while the
-- operator saw "contacts approved, but no invite tasks" with no explanation.
-- The BFF now notifies the owner; without this type the insert violates the
-- CHECK and degrades to the `contact_replied` fallback in
-- selltonai/src/lib/linkedin-notifications.ts (visible, wrong label + icon).
-- ============================================================

-- Drop BOTH possible names (see header). IF EXISTS makes each a safe no-op.
ALTER TABLE public.notifications
  DROP CONSTRAINT IF EXISTS notifications_type_check_crm_next;

ALTER TABLE public.notifications
  DROP CONSTRAINT IF EXISTS notifications_type_check;

-- Rebuild under the temporary name first, mirroring 353's own pattern.
ALTER TABLE public.notifications
  ADD CONSTRAINT notifications_type_check_crm_next CHECK (
    type IN (
      'task_assigned',
      'task_due',
      'contact_replied',
      'campaign_alert',
      'campaign_completed',
      'budget_warning',
      'budget_critical',
      'daily_briefing',
      'weekly_report',
      'approval_needed',
      'system_alert',
      'phone_discovery_complete',
      'phone_discovery_failed',
      'enrichment_complete',
      'research_complete',
      'deep_research_settings_changed',
      'linkedin_account_credentials_expired',
      'linkedin_account_restricted',
      'linkedin_invite_accepted',
      'linkedin_cap_reached',
      'linkedin_sequence_completed',
      'linkedin_sequence_paused_on_reply',
      'linkedin_campaign_account_missing',
      'deal_created',
      'deal_stage_changed',
      'deal_owner_changed'
    )
  ) NOT VALID;

-- Existing rows were already validated against 353's list, which this one is a
-- strict superset of, so validation cannot fail on historical data.
ALTER TABLE public.notifications
  VALIDATE CONSTRAINT notifications_type_check_crm_next;

-- Settle on the canonical name so the next migration finds what it expects.
ALTER TABLE public.notifications
  RENAME CONSTRAINT notifications_type_check_crm_next TO notifications_type_check;

-- Verify after apply. Expect EXACTLY ONE row, named notifications_type_check,
-- whose definition contains 'linkedin_campaign_account_missing':
-- SELECT conname, pg_get_constraintdef(oid) FROM pg_constraint
-- WHERE conrelid = 'public.notifications'::REGCLASS AND contype = 'c'
--   AND conname LIKE 'notifications_type_check%';
