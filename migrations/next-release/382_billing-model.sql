-- ============================================================
-- Migration: billing-model (stage: next-release/382)
-- Date:      2026-09-26
-- Ticket:    KAN-317 (billing model decisions B-113 to B-124)
-- Purpose:   Settings, product state, trials, credits and referrals for the
--            new billing model: one price table, the web trial per org, the
--            phone trial and activation per person, a credits ledger and the
--            referral record.
-- Projects:  selltonai-database/supabase (owner). Writers today: backoffice
--            (settings page, trial, credits, product-state override, phone
--            activation per seat). Readers later, in their own releases:
--            selltonai-modal (invoices), selltonai (billing page, trial),
--            the mobile service (phone trial and activation, referrals).
-- Contract:  Additive only. Three new tables, nullable columns on four
--            existing tables, no existing column, constraint, RPC or policy
--            changed. Nothing reads the new objects until Modal and the web
--            ship their releases, so applying this changes no invoice.
--            Re-running it is a no-op.
-- Depends:   public.organization, public.billing_customers (243),
--            public.org_seats (306), public.activation_fees (307),
--            public.update_updated_at_column() (release_1.0.0; last
--            re-declared by 300).
-- Deploy:    This migration first, then the backoffice (it tolerates the
--            reverse order: reads fall back, writes refuse with a message).
-- ============================================================

-- organization is read on every request; fail fast instead of queueing behind
-- a long transaction (the runner rolls the file back and it can be re-run).
SET LOCAL lock_timeout = '10s';

-- Prices, the web and phone trials (length and credit, set apart), referral
-- credit and cap: one row per key.
-- The weekly seat rate is never stored; it is the 4-week price divided by 4.
CREATE TABLE IF NOT EXISTS public.billing_settings (
  key         text PRIMARY KEY,
  value       numeric(12,2) NOT NULL CHECK (value >= 0),
  unit        text NOT NULL CHECK (unit IN ('usd', 'days', 'count')),
  description text,
  updated_by  text,
  updated_at  timestamptz NOT NULL DEFAULT now()
);

-- Stage and production seed the same prices; anything different is set on the
-- backoffice settings page. ON CONFLICT keeps values already changed there.
INSERT INTO public.billing_settings (key, value, unit, description) VALUES
  ('activation_fee_tier1_usd',   500.00, 'usd',   'Activation for 1-2 people; waivable by code'),
  ('activation_fee_tier2_usd',  1500.00, 'usd',   'Activation for 2-3 people, small teams; waivable by code'),
  ('infrastructure_fee_4w_usd',   33.00, 'usd',   'Every 4 weeks, upfront, web orgs only (8.25 a week today)'),
  ('seat_web_4w_usd',             15.00, 'usd',   'Per person every 4 weeks when the org is on the web; a week = a quarter of it'),
  ('seat_mobile_4w_usd',           6.00, 'usd',   'Per activated person every 4 weeks, phone-only orgs; a week = a quarter of it'),
  ('trial_web_days',                  7, 'days',  'Web trial length, per workspace'),
  ('trial_web_credit_usd',        40.00, 'usd',   'Usage covered during the web trial'),
  ('trial_mobile_days',               7, 'days',  'Phone trial length, per person'),
  ('trial_mobile_credit_usd',     10.00, 'usd',   'Usage covered during the phone trial, per person'),
  ('referral_credit_usd',         10.00, 'usd',   'To the referrer once the referred person activates past the free usage'),
  ('referral_max',                    5, 'count', 'Referrals credited per person; staff may raise it per org')
ON CONFLICT (key) DO NOTHING;

-- The web trial, per org.
ALTER TABLE public.billing_customers
  ADD COLUMN IF NOT EXISTS trial_started_at timestamptz,
  ADD COLUMN IF NOT EXISTS trial_ends_at    timestamptz,
  ADD COLUMN IF NOT EXISTS trial_granted_by text;          -- null: started by a card; else the staff actor

-- Product state, written by the apps, overridden by staff for fixes.
ALTER TABLE public.organization
  ADD COLUMN IF NOT EXISTS web_billing_started_at    timestamptz,  -- first campaign or prospecting on the web
  ADD COLUMN IF NOT EXISTS mobile_billing_started_at timestamptz,  -- first person activated on the phone
  ADD COLUMN IF NOT EXISTS billing_cycle_anchor      date,         -- the 4-week clock starts here
  ADD COLUMN IF NOT EXISTS fees_paused_at            timestamptz,  -- "pause my account": no fixed fees while set
  ADD COLUMN IF NOT EXISTS referral_limit            integer CHECK (referral_limit IS NULL OR referral_limit >= 0);

-- The phone trial and activation, per person.
ALTER TABLE public.org_seats
  ADD COLUMN IF NOT EXISTS mobile_trial_started_at timestamptz,
  ADD COLUMN IF NOT EXISTS mobile_trial_ends_at    timestamptz,
  ADD COLUMN IF NOT EXISTS mobile_activated_at     timestamptz;   -- the person pays the phone seat from here

-- Activation tier and how it was paid (the amount columns already exist).
ALTER TABLE public.activation_fees
  ADD COLUMN IF NOT EXISTS tier text CHECK (tier IS NULL OR tier IN ('tier1', 'tier2', 'invoiced'));

-- Credits: trial, referral, manual. Modal draws remaining_usd down on the weekly invoice.
CREATE TABLE IF NOT EXISTS public.billing_credits (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  kind            text NOT NULL CHECK (kind IN ('trial', 'referral', 'manual')),
  amount_usd      numeric(10,2) NOT NULL CHECK (amount_usd > 0),
  remaining_usd   numeric(10,2) NOT NULL CHECK (remaining_usd >= 0),
  source          text,                       -- referral id, discount code, or the staff note
  expires_at      timestamptz,
  created_by      text NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS billing_credits_org_open_idx
  ON public.billing_credits (organization_id) WHERE remaining_usd > 0;

-- Who referred whom. The apps write it; the backoffice shows it and credits from it.
CREATE TABLE IF NOT EXISTS public.billing_referrals (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  referrer_org_id    text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  referrer_user_id   text NOT NULL,
  referred_org_id    text REFERENCES public.organization(id) ON DELETE SET NULL,
  referred_email     text NOT NULL,
  status             text NOT NULL DEFAULT 'invited' CHECK (status IN ('invited', 'card_added', 'activated', 'credited', 'rejected')),
  credit_id          uuid REFERENCES public.billing_credits(id) ON DELETE SET NULL,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS billing_referrals_referrer_idx
  ON public.billing_referrals (referrer_org_id, referrer_user_id);

-- updated_at triggers, the 306 pattern.
DROP TRIGGER IF EXISTS update_billing_settings_updated_at ON public.billing_settings;
CREATE TRIGGER update_billing_settings_updated_at
  BEFORE UPDATE ON public.billing_settings
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_billing_credits_updated_at ON public.billing_credits;
CREATE TRIGGER update_billing_credits_updated_at
  BEFORE UPDATE ON public.billing_credits
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_billing_referrals_updated_at ON public.billing_referrals;
CREATE TRIGGER update_billing_referrals_updated_at
  BEFORE UPDATE ON public.billing_referrals
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

-- RLS and grants, the 376 pattern: service_role only. anon and authenticated get
-- nothing; a later release that reads these with a user JWT adds its own grant
-- and policy.
ALTER TABLE public.billing_settings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.billing_settings FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.billing_settings TO service_role;

ALTER TABLE public.billing_credits ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.billing_credits FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.billing_credits TO service_role;

ALTER TABLE public.billing_referrals ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.billing_referrals FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.billing_referrals TO service_role;

-- Verify (after each run; the second run must change nothing):
-- SELECT count(*) = 11 AS settings_seeded FROM public.billing_settings;
-- SELECT column_name FROM information_schema.columns
--  WHERE table_schema = 'public' AND table_name = 'organization'
--    AND column_name IN ('web_billing_started_at', 'mobile_billing_started_at',
--                        'billing_cycle_anchor', 'fees_paused_at', 'referral_limit');  -- 5 rows
-- SELECT column_name FROM information_schema.columns
--  WHERE table_schema = 'public' AND table_name = 'org_seats'
--    AND column_name LIKE 'mobile_%';  -- 3 rows
-- SELECT relname, relrowsecurity FROM pg_class
--  WHERE relnamespace = 'public'::regnamespace
--    AND relname IN ('billing_settings', 'billing_credits', 'billing_referrals');  -- all true
