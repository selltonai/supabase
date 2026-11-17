-- ============================================================
-- Migration: 446_billing-v2-cycle-charges (stage: next-release/446; renumber at promotion if 446 is taken)
-- Date:      2026-11-17
-- Purpose:   Billing v2 (PLAN_BILLING_V2_DELIVERY_2026_10_26, section 3.1): the 4-week cycle with fees charged
--            upfront.
--            1. organization.billing_model: the workspace's billing cohort, decided once by Modal and never
--               changed by it: 'v1' (today's weekly fees, every workspace whose billing started before Modal's
--               BILLING_V2_FROM) or 'v2' (the cycle, a workspace whose billing starts at or after it). NULL: not
--               decided yet.
--            2. org_seats.seat_kind ('web' or 'phone'), seat_kind_changed_at, seat_kind_changed_by.
--            3. billing_cycle_charges: the ledger, one row per fee per cycle, with a unique key on
--               (organization_id, cycle_start, charge_key) so a fee is never charged twice even if a job runs
--               twice.
--            4. billing_allowance_deductions: what a workspace's grant (a workspace_allowances row of kind
--               pilot, prepaid or goodwill, 427) has paid for: on v2 one row per fee and per usage week, on v1
--               one row per weekly invoice, with a unique key on (allowance_id, deduction_key). The limit's remaining amount is always
--               workspace_allowances.amount_usd minus the sum of amount_usd here for that allowance_id.
-- Projects:  selltonai-database/supabase (owner). selltonai-modal reads billing_model, billing_cycle_anchor (382),
--            seat_kind and reads and writes billing_model, billing_cycle_charges and
--            billing_allowance_deductions, only with its env setting BILLING_V2_FROM set. backoffice later: shows
--            the ledger, and shows billing_allowance_deductions as what a prepaid limit has spent
--            (organization_id, allowance_id, amount_usd, covers, deduction_key, period_start, created_at).
--            selltonai later: writes seat_kind on the Team page. The mobile service and the engine: none.
-- Contract:  Additive. Two new tables, one column on organization, three on org_seats. billing_model is NULL for
--            every existing workspace until Modal decides it; every existing seat is 'web', except the seats of workspaces that signed up on the phone
--            (organization.signup_source = 'mobile', when that column exists), which are 'phone'; that backfill
--            runs once, with the column. Nothing reads the new objects until Modal's BILLING_V2_FROM is set, so
--            applying this changes no invoice. Re-running it is a no-op. Both new tables are service role only:
--            RLS on with no policies, and anon and authenticated get no table privileges.
--            billing_allowance_deductions.allowance_id is a workspace_allowances id without a foreign key, so
--            this file does not depend on 427 and 427's rollback is not blocked.
--            Not in this file: seat rows for members who have none (the plan's "seats for every member"); Modal
--            charges no cycle fee to a workspace that still has such a member.
-- Depends:   public.organization, public.billing_invoices (243), public.org_seats (306),
--            public.update_updated_at_column() (release_1.0.0; last re-declared by 300). 382 (billing_settings,
--            organization.billing_cycle_anchor) is read by Modal, not by this file.
-- Deploy:    This migration first, then Modal (Modal tolerates the reverse order: with BILLING_V2_FROM unset it
--            reads nothing new; with it set and the objects missing it bills a new workspace nothing and logs
--            the error, and bills every workspace that started before the cutover as today).
-- Rollback:  rollback/446_billing-v2-cycle-charges.rollback.sql
-- ============================================================

-- organization is read on every request; fail fast instead of queueing behind a long transaction (the runner
-- rolls the file back and it can be re-run).
SET LOCAL lock_timeout = '10s';

-- 1. The cohort per workspace ---------------------------------------------------------------------------
ALTER TABLE public.organization
  ADD COLUMN IF NOT EXISTS billing_model text
    CONSTRAINT organization_billing_model_check CHECK (billing_model IS NULL OR billing_model IN ('v1', 'v2'));

-- 2. Seat kind ------------------------------------------------------------------------------------------
-- The column and its one-time backfill go together: a re-run must never turn a seat back to 'phone' after the
-- Team page changed it.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema = 'public' AND table_name = 'org_seats' AND column_name = 'seat_kind'
  ) THEN
    ALTER TABLE public.org_seats
      ADD COLUMN seat_kind text NOT NULL DEFAULT 'web'
        CONSTRAINT org_seats_seat_kind_check CHECK (seat_kind IN ('web', 'phone'));

    IF EXISTS (
      SELECT 1 FROM information_schema.columns
       WHERE table_schema = 'public' AND table_name = 'organization' AND column_name = 'signup_source'
    ) THEN
      EXECUTE $backfill$
        UPDATE public.org_seats AS s
           SET seat_kind = 'phone'
          FROM public.organization AS o
         WHERE o.id = s.organization_id
           AND o.signup_source = 'mobile'
      $backfill$;
    END IF;
  END IF;
END $$;

ALTER TABLE public.org_seats
  ADD COLUMN IF NOT EXISTS seat_kind_changed_at timestamptz,
  ADD COLUMN IF NOT EXISTS seat_kind_changed_by text;

-- 3. The ledger -----------------------------------------------------------------------------------------
-- charge_key: 'infrastructure', 'seat:<org_seats.id>', 'seat:<org_seats.id>:upgrade' (phone to web inside the
-- cycle), or the marker with no money 'waived:paused' (fees paused at the cycle start), which makes the whole
-- cycle free of fees.
-- status: 'reserved' (written before the Stripe invoice), 'invoiced' (on billing_invoices row invoice_id),
-- 'waived' (nothing to pay: a marker, or a price of 0.00).
CREATE TABLE IF NOT EXISTS public.billing_cycle_charges (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  cycle_start     date NOT NULL CHECK (extract(isodow FROM cycle_start) = 1),   -- a Monday
  charge_key      text NOT NULL
    CHECK (charge_key ~ '^(infrastructure|seat:[^:]+(:upgrade)?|waived:paused)$'),
  seat_kind       text CHECK (seat_kind IS NULL OR seat_kind IN ('web', 'phone')),
  weeks           integer NOT NULL CHECK (weeks BETWEEN 0 AND 4),
  amount_usd      numeric(10,2) NOT NULL CHECK (amount_usd >= 0),
  status          text NOT NULL DEFAULT 'reserved' CHECK (status IN ('reserved', 'invoiced', 'waived')),
  invoice_id      uuid REFERENCES public.billing_invoices(id) ON DELETE SET NULL,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT billing_cycle_charges_once_per_cycle UNIQUE (organization_id, cycle_start, charge_key)
);

CREATE INDEX IF NOT EXISTS billing_cycle_charges_invoice_idx
  ON public.billing_cycle_charges (invoice_id) WHERE invoice_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS billing_cycle_charges_reserved_idx
  ON public.billing_cycle_charges (created_at) WHERE status = 'reserved';

DROP TRIGGER IF EXISTS update_billing_cycle_charges_updated_at ON public.billing_cycle_charges;
CREATE TRIGGER update_billing_cycle_charges_updated_at
  BEFORE UPDATE ON public.billing_cycle_charges
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- 4. What a prepaid limit has paid for -------------------------------------------------------------------
-- deduction_key: on v2 'fee:<cycle_start>:<charge_key>' (a billing_cycle_charges fee) or
-- 'usage:<period_start date>' (the usage of the invoice week that starts then); on v1
-- 'invoice:<period_start date>' (the whole weekly invoice: usage and the weekly fees).
-- covers: 'fee', 'usage' or 'invoice'.
-- status: 'reserved' (written before the invoice record), 'applied' (on billing_invoices row invoice_id, whose
-- line items show it as action 'prepaid_limit'). Both count as spent.
CREATE TABLE IF NOT EXISTS public.billing_allowance_deductions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  allowance_id    uuid NOT NULL,                                   -- workspace_allowances.id (427), no key
  deduction_key   text NOT NULL
    CHECK (deduction_key ~ '^(fee:[0-9]{4}-[0-9]{2}-[0-9]{2}:.+|(usage|invoice):[0-9]{4}-[0-9]{2}-[0-9]{2})$'),
  covers          text NOT NULL CHECK (covers IN ('fee', 'usage', 'invoice')),
  amount_usd      numeric(12,2) NOT NULL CHECK (amount_usd > 0),
  status          text NOT NULL DEFAULT 'reserved' CHECK (status IN ('reserved', 'applied')),
  invoice_id      uuid REFERENCES public.billing_invoices(id) ON DELETE SET NULL,
  period_start    timestamptz NOT NULL,                            -- the invoice week it was deducted in
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT billing_allowance_deductions_once UNIQUE (allowance_id, deduction_key)
);

CREATE INDEX IF NOT EXISTS billing_allowance_deductions_org_idx
  ON public.billing_allowance_deductions (organization_id, created_at DESC);

DROP TRIGGER IF EXISTS update_billing_allowance_deductions_updated_at ON public.billing_allowance_deductions;
CREATE TRIGGER update_billing_allowance_deductions_updated_at
  BEFORE UPDATE ON public.billing_allowance_deductions
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- Access: the service role only -------------------------------------------------------------------------
-- Supabase grants new tables to anon and authenticated by default; take that away. RLS is on with no policies on
-- purpose: Modal and the backoffice use the service role, and browser keys see nothing.
REVOKE ALL ON TABLE public.billing_cycle_charges, public.billing_allowance_deductions
  FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.billing_cycle_charges, public.billing_allowance_deductions TO service_role;
ALTER TABLE public.billing_cycle_charges ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.billing_allowance_deductions ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.billing_cycle_charges IS
  'Billing v2 ledger: one row per fee per 4-week cycle (infrastructure, seat:<id>, seat:<id>:upgrade, or a waived:* marker). UNIQUE (organization_id, cycle_start, charge_key) is what stops a double charge. Written by Modal with the service role only.';
COMMENT ON TABLE public.billing_allowance_deductions IS
  'Billing: what a grant (workspace_allowances kind pilot, prepaid or goodwill) has paid for: per fee and usage week on v2, per weekly invoice on v1. Remaining limit = workspace_allowances.amount_usd minus sum(amount_usd) for the allowance_id. UNIQUE (allowance_id, deduction_key) stops a double deduction. Written by Modal with the service role only.';
COMMENT ON COLUMN public.organization.billing_model IS
  'Billing cohort, decided once by Modal: v1 (weekly fees in arrears, billing started before BILLING_V2_FROM) or v2 (4-week cycle, fees upfront). NULL: not decided yet.';
COMMENT ON COLUMN public.org_seats.seat_kind IS
  'web | phone. Sets the 4-week seat price (billing_settings seat_web_4w_usd, seat_mobile_4w_usd) in billing v2.';

-- Fail the file if a browser key can still reach a new table.
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['billing_cycle_charges', 'billing_allowance_deductions'] LOOP
    IF has_table_privilege('anon', 'public.' || t, 'SELECT')
       OR has_table_privilege('authenticated', 'public.' || t, 'SELECT')
       OR has_table_privilege('anon', 'public.' || t, 'INSERT')
       OR has_table_privilege('authenticated', 'public.' || t, 'INSERT')
       OR has_table_privilege('anon', 'public.' || t, 'UPDATE')
       OR has_table_privilege('authenticated', 'public.' || t, 'UPDATE')
       OR has_table_privilege('anon', 'public.' || t, 'DELETE')
       OR has_table_privilege('authenticated', 'public.' || t, 'DELETE') THEN
      RAISE EXCEPTION '446: anon or authenticated can still read or write %', t;
    END IF;
  END LOOP;
END $$;

-- Verify (read-only):
-- select billing_model, count(*) from public.organization group by 1;            -- NULL only
-- select seat_kind, count(*) from public.org_seats group by 1;                   -- web, and phone for mobile signups
-- select relname, relrowsecurity from pg_class
--  where relname in ('billing_cycle_charges', 'billing_allowance_deductions');   -- two rows, both true
-- select has_table_privilege('anon', 'public.billing_cycle_charges', 'SELECT'),            -- false
--        has_table_privilege('service_role', 'public.billing_cycle_charges', 'INSERT');    -- true
