-- Reverses 446. Unset Modal's BILLING_V2_FROM first (with it unset Modal reads none of this), and mind that Modal
-- then bills every workspace weekly again, also for weeks a cycle already paid upfront.
-- Lossy once rows exist: dropping billing_cycle_charges drops the record of every cycle fee already charged, and
-- with it the protection against charging the same cycle again; dropping billing_allowance_deductions drops what
-- every prepaid limit has spent. Copy both tables first if they have rows. Dropping seat_kind loses which seats
-- are phone seats, and billing_cohort which workspaces keep the old price.
SET LOCAL lock_timeout = '10s';

DROP TABLE IF EXISTS public.billing_allowance_deductions;
DROP TABLE IF EXISTS public.billing_cycle_charges;

ALTER TABLE public.org_seats
  DROP COLUMN IF EXISTS seat_kind_changed_by,
  DROP COLUMN IF EXISTS seat_kind_changed_at,
  DROP COLUMN IF EXISTS seat_kind;

ALTER TABLE public.organization
  DROP COLUMN IF EXISTS billing_cohort;
