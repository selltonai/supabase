-- KAN-282: carry stage's CRM signal activity into production without changing
-- the already-applied release_1.3.0/369 migration. Modal and the frontend may
-- use this activity after the production schema deployment. Migration 371
-- restores the guarded record_crm_deal_activity_for_contact RPC first.
-- Existing rows are unchanged; only the allowed activity-type check expands.

ALTER TABLE public.deal_activities
  ADD CONSTRAINT deal_activities_type_check_v4_next CHECK (
    activity_type IN (
      'deal_created', 'stage_change', 'amount_change', 'owner_change',
      'nurture_change', 'snooze_change', 'note', 'email_in', 'email_out',
      'linkedin_in', 'linkedin_out', 'task_created', 'task_completed',
      'sequence_stopped', 'linkedin_connected', 'decision', 'signal'
    )
  ) NOT VALID;

ALTER TABLE public.deal_activities
  VALIDATE CONSTRAINT deal_activities_type_check_v4_next;

ALTER TABLE public.deal_activities
  DROP CONSTRAINT IF EXISTS deal_activities_type_check;

ALTER TABLE public.deal_activities
  RENAME CONSTRAINT deal_activities_type_check_v4_next TO deal_activities_type_check;
