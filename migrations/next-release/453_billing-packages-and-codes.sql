-- ============================================================
-- Migration: 453_billing-packages-and-codes (stage: next-release/453; renumber at promotion if 453 is taken)
-- Date:      2026-11-27
-- Ticket:    KAN-borce27 (PLAN_YEAR_END_PACKAGES_AND_ONBOARDING_2026_11_27, T1; decisions B1-B27)
-- Purpose:   The packages a new workspace buys at activation, and the activation codes for invoice deals.
--            1. billing_packages: one row per package (solo, pilot, team, scale): the price, the usage grant it
--               gives and for how many days, and whether the onboarding wall shows it. Seeded with B1's terms;
--               edited on the backoffice's /billing/settings. A grant already written keeps its own terms.
--            2. package_codes: an activation code for a deal paid by invoice (B3): a package, or its own grant and
--               days (a custom deal), the invoiced price, the one email domain or address that may redeem it, and
--               who redeemed it. Issued on the backoffice's Codes screen; redeemed only through
--               redeem_package_code (454).
--            3. package_code_attempts: every refused redemption, per workspace (the 10-in-24-hours limit).
--            4. activation_fees: package_id, source (stripe_checkout, package_code, discount_code, comp),
--               invoice_ref, invoiced_price_cents. NULL on every existing row.
-- Projects:  selltonai-database/supabase (owner). backoffice writes billing_packages and package_codes and reads
--            all four. selltonai reads billing_packages (the wall, checkout's price) and calls the 454 functions.
--            selltonai-modal reads activation_fees.source and package_id later (nothing today). The mobile service
--            and the engine: none.
-- Contract:  Additive. Three new tables (four seeded rows), four nullable columns on activation_fees; no existing
--            column, constraint or row changes. Re-running it is a no-op and keeps packages staff edited. The three
--            tables are service role only: RLS on with no policies, and anon and authenticated get no table
--            privileges. package_codes.recommendation_id is a cs_recommendations id (422) and
--            package_code_attempts.organization_id an organization id, both without a foreign key, so neither
--            blocks a rollback or loses the record of an attempt when a workspace goes.
--            Application code: none must ship together with this file (nothing reads the new objects until the
--            app, the backoffice and 454 ship).
-- Depends:   public.organization (release_1.0.0), public.activation_fees (307),
--            public.update_updated_at_column() (release_1.0.0; last re-declared by 300).
-- Deploy:    This file, then 454, then Modal, the backoffice and the app (plan section 7).
-- Rollback:  rollback/453_billing-packages-and-codes.rollback.sql (roll 454 back first).
-- ============================================================

-- organization is read on every request; fail fast instead of queueing behind a long transaction (the runner rolls
-- the file back and it can be re-run).
SET LOCAL lock_timeout = '10s';

-- 1. Packages -------------------------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.billing_packages (
  id text PRIMARY KEY CHECK (id IN ('solo', 'pilot', 'team', 'scale')),
  label text NOT NULL CHECK (char_length(label) BETWEEN 1 AND 80),
  -- What the workspace pays (by card on the wall, or on the invoice for a code).
  price_usd numeric(12, 2) NOT NULL CHECK (price_usd > 0),
  -- The usage grant it gives: the workspace_allowances amount, for validity_days from payment (card) or approval
  -- (code).
  grant_usd numeric(12, 2) NOT NULL CHECK (grant_usd > 0),
  validity_days integer NOT NULL CHECK (validity_days > 0),
  -- Offered on the onboarding wall by card. The others are sold with a code.
  shown_on_wall boolean NOT NULL DEFAULT false,
  -- false: neither on the wall nor for new codes. Codes already issued keep their package.
  active boolean NOT NULL DEFAULT true,
  sort smallint NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now(),
  -- 'migration:453', or the staff user's sign-in email.
  updated_by text
);

DROP TRIGGER IF EXISTS update_billing_packages_updated_at ON public.billing_packages;
CREATE TRIGGER update_billing_packages_updated_at
  BEFORE UPDATE ON public.billing_packages
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- B1's terms. A re-run adds nothing and leaves a package staff changed as it is.
INSERT INTO public.billing_packages (id, label, price_usd, grant_usd, validity_days, shown_on_wall, active, sort, updated_by)
VALUES ('solo',  'Solo',   500.00,  250.00,  90, true,  true, 1, 'migration:453'),
       ('pilot', 'Pilot', 2000.00, 1000.00,  90, true,  true, 2, 'migration:453'),
       ('team',  'Team',  4000.00, 2000.00,  90, false, true, 3, 'migration:453'),
       ('scale', 'Scale', 8000.00, 4000.00, 180, false, true, 4, 'migration:453')
ON CONFLICT (id) DO NOTHING;

-- 2. Activation codes ------------------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.package_codes (
  -- Upper case, no spaces (for example SELL-TEAM-7KQ4-M2XD). redeem_package_code upper-cases what is typed.
  code text PRIMARY KEY CHECK (char_length(code) BETWEEN 4 AND 64 AND code = upper(code) AND code !~ '\s'),
  -- A package, or a custom deal: then grant_usd and validity_days are the deal's own. When both are set on a
  -- package code, the code's own values win.
  package_id text REFERENCES public.billing_packages(id),
  grant_usd numeric(12, 2) CHECK (grant_usd IS NULL OR grant_usd > 0),
  validity_days integer CHECK (validity_days IS NULL OR validity_days > 0),
  -- The invoiced amount (recorded on the activation_fees row as invoiced_price_cents).
  price_usd numeric(12, 2) NOT NULL CHECK (price_usd >= 0),
  -- Who may redeem it: everyone at one domain (acme.com), or one address. Exactly one, lower case.
  email_domain text CHECK (email_domain IS NULL OR (char_length(email_domain) BETWEEN 3 AND 253
                                                    AND email_domain = lower(email_domain)
                                                    AND email_domain LIKE '%.%'
                                                    AND email_domain NOT LIKE '%@%')),
  email_exact text CHECK (email_exact IS NULL OR (char_length(email_exact) BETWEEN 3 AND 320
                                                  AND email_exact = lower(email_exact)
                                                  AND email_exact LIKE '%_@_%')),
  invoice_ref text NOT NULL CHECK (char_length(invoice_ref) BETWEEN 1 AND 200),
  note text CHECK (note IS NULL OR char_length(note) <= 2000),
  -- Issue + 30 days by default (the backoffice sets it).
  expires_at timestamptz NOT NULL,
  -- false: deactivated on the Codes screen.
  active boolean NOT NULL DEFAULT true,
  -- The staff user's sign-in email.
  created_by text NOT NULL CHECK (char_length(created_by) BETWEEN 1 AND 320),
  created_at timestamptz NOT NULL DEFAULT now(),
  -- Set once, by redeem_package_code. The workspace may be deleted later; the code stays used.
  redeemed_org_id text REFERENCES public.organization(id) ON DELETE SET NULL,
  -- The Clerk user id of the person who redeemed it.
  redeemed_by text,
  redeemed_at timestamptz,
  -- The cs_recommendations row (422) the redemption proposed; no key.
  recommendation_id uuid,
  CONSTRAINT package_codes_email_check CHECK ((email_domain IS NULL) <> (email_exact IS NULL)),
  CONSTRAINT package_codes_terms_check CHECK (
    package_id IS NOT NULL OR (grant_usd IS NOT NULL AND validity_days IS NOT NULL)
  ),
  CONSTRAINT package_codes_redeemed_check CHECK (redeemed_org_id IS NULL OR redeemed_at IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS package_codes_redeemed_org_idx
  ON public.package_codes (redeemed_org_id)
  WHERE redeemed_org_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS package_codes_created_idx
  ON public.package_codes (created_at DESC);

-- 3. Refused redemptions ---------------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.package_code_attempts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  -- The workspace that tried; no key, so the record outlives it.
  organization_id text,
  -- What was typed, upper-cased and cut to 200 characters.
  code_tried text,
  -- redeem_package_code's refusal: too_many_attempts, not_found, inactive, expired, used, email_mismatch,
  -- archived, existing_cohort, already_activated_with_grant, package_pending.
  reason text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS package_code_attempts_org_idx
  ON public.package_code_attempts (organization_id, created_at);

-- 4. The activation record -------------------------------------------------------------------------------

ALTER TABLE public.activation_fees
  ADD COLUMN IF NOT EXISTS package_id text,
  ADD COLUMN IF NOT EXISTS source text
    CONSTRAINT activation_fees_source_check
      CHECK (source IS NULL OR source IN ('stripe_checkout', 'package_code', 'discount_code', 'comp')),
  ADD COLUMN IF NOT EXISTS invoice_ref text,
  ADD COLUMN IF NOT EXISTS invoiced_price_cents integer
    CONSTRAINT activation_fees_invoiced_price_check
      CHECK (invoiced_price_cents IS NULL OR invoiced_price_cents >= 0);

-- A refund or dispute finds its activation by the payment intent (end_package_grant_for_payment, 454).
CREATE INDEX IF NOT EXISTS idx_activation_fees_payment_intent
  ON public.activation_fees (stripe_payment_intent_id)
  WHERE stripe_payment_intent_id IS NOT NULL;

-- Access: the service role only ----------------------------------------------------------------------------
-- Supabase grants new tables to anon and authenticated by default; take that away. RLS is on with no policies on
-- purpose: the app and the backoffice read and write with the service role, and browser keys see nothing.

REVOKE ALL ON TABLE public.billing_packages, public.package_codes, public.package_code_attempts
  FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.billing_packages, public.package_codes, public.package_code_attempts TO service_role;

ALTER TABLE public.billing_packages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.package_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.package_code_attempts ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.billing_packages IS
  'Activation packages (B1): price, the usage grant it gives (grant_usd for validity_days) and whether the onboarding wall offers it by card. Edited on the backoffice''s /billing/settings; a grant already written keeps its own terms. Service role only.';
COMMENT ON TABLE public.package_codes IS
  'Activation codes for invoice deals (B3): a package or a custom grant and days, the invoiced price, the one email domain or address that may redeem it, and who redeemed it. Issued by the backoffice; redeemed only through redeem_package_code (454). Service role only.';
COMMENT ON TABLE public.package_code_attempts IS
  'Refused package code redemptions per workspace, written by redeem_package_code (454); 10 in 24 hours stops further tries. Service role only.';
COMMENT ON COLUMN public.activation_fees.package_id IS
  '453: the billing_packages id the activation bought (no key: the row keeps it if the package goes). NULL: before packages, or a custom code.';
COMMENT ON COLUMN public.activation_fees.source IS
  '453: stripe_checkout (activate_package_checkout), package_code (redeem_package_code), discount_code (a 100% code), comp (the backoffice). NULL: written before 453.';
COMMENT ON COLUMN public.activation_fees.invoice_ref IS
  '453: the invoice a package code was sold on.';
COMMENT ON COLUMN public.activation_fees.invoiced_price_cents IS
  '453: the invoiced price of a package code, in cents (amount_paid_cents stays 0: the money is not taken in Stripe).';

-- Fail the file if a browser key can still reach a new table.
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['billing_packages', 'package_codes', 'package_code_attempts'] LOOP
    IF has_table_privilege('anon', 'public.' || t, 'SELECT')
       OR has_table_privilege('authenticated', 'public.' || t, 'SELECT')
       OR has_table_privilege('anon', 'public.' || t, 'INSERT')
       OR has_table_privilege('authenticated', 'public.' || t, 'INSERT')
       OR has_table_privilege('anon', 'public.' || t, 'UPDATE')
       OR has_table_privilege('authenticated', 'public.' || t, 'UPDATE')
       OR has_table_privilege('anon', 'public.' || t, 'DELETE')
       OR has_table_privilege('authenticated', 'public.' || t, 'DELETE') THEN
      RAISE EXCEPTION '453: anon or authenticated can still read or write %', t;
    END IF;
  END LOOP;
END $$;

-- Verify (read-only):
-- select id, label, price_usd, grant_usd, validity_days, shown_on_wall, active from public.billing_packages order by sort;
--   -> solo 500/250/90 shown, pilot 2000/1000/90 shown, team 4000/2000/90, scale 8000/4000/180
-- select relname, relrowsecurity from pg_class
--  where relname in ('billing_packages', 'package_codes', 'package_code_attempts');   -- three rows, all true
-- select source, count(*) from public.activation_fees group by 1;                       -- NULL only
-- select has_table_privilege('anon', 'public.package_codes', 'SELECT'),                 -- false
--        has_table_privilege('service_role', 'public.package_codes', 'INSERT');         -- true
