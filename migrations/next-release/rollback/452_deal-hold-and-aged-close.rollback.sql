-- Reverses 452: the hold function and the index are dropped, and the activity type check is put back to its 384 list.
-- The old check is added NOT VALID, so 'aged_close' and 'call_connected' rows written while 452 was live stay as they
-- are (no data is deleted); new rows of those two types are refused again. The Modal and app readers fall back to
-- plain selects of public.deals when the function is missing, so they may stay live.
SET LOCAL lock_timeout = '10s';

DROP FUNCTION IF EXISTS public.deal_hold_companies(text, uuid[], timestamptz);

DROP INDEX IF EXISTS public.idx_deals_company_closed_at;

ALTER TABLE public.deal_activities
  DROP CONSTRAINT IF EXISTS deal_activities_type_check;

ALTER TABLE public.deal_activities
  ADD CONSTRAINT deal_activities_type_check CHECK (
    activity_type IN (
      'deal_created', 'stage_change', 'amount_change', 'owner_change',
      'nurture_change', 'snooze_change', 'note', 'email_in', 'email_out',
      'linkedin_in', 'linkedin_out', 'task_created', 'task_completed',
      'sequence_stopped', 'linkedin_connected', 'decision', 'signal'
    )
  ) NOT VALID;
