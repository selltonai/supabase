-- Migrations 453 and 454's contract bootstrap: the tables the three functions touch, as their own migrations leave
-- them (only the columns 453, 454 and the contract need). The runner then applies the real 307 (activation_fees),
-- 422 (cs_recommendations), 427 (workspace_allowances), 428 (workspace_deletions) and 446
-- (organization.billing_cohort, billing_allowance_deductions) on top. Disposable database only.
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated; END IF;
END $$;
-- Supabase's default privileges: every new table and function is granted to anon and authenticated. Without these
-- the migrations' revoke checks would prove nothing.
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

-- organization: the base table (full_schema), deleted (115), the onboarding and dispatch columns (302), the
-- work-access override (324), signup_source (379) and the cycle anchor (382). billing_cohort comes from 446.
CREATE TABLE public.organization (
  id text PRIMARY KEY,
  name text,
  deleted boolean NOT NULL DEFAULT false,
  activation_paid_at timestamptz,
  dispatch_suspended boolean NOT NULL DEFAULT false,
  dispatch_suspended_reason text,
  dispatch_suspended_at timestamptz,
  work_access_mode text NOT NULL DEFAULT 'auto'
    CONSTRAINT organization_work_access_mode_check CHECK (work_access_mode IN ('auto', 'force_allow', 'force_block')),
  work_access_reason text,
  work_access_until timestamptz,
  work_access_updated_by text,
  work_access_updated_at timestamptz,
  signup_source text,
  billing_cycle_anchor date
);

-- release_1.0.0, as last re-declared by 300.
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- discount_codes: only the key 307 references.
CREATE TABLE public.discount_codes (code text PRIMARY KEY);

-- email_sequence_steps as 340 and 344 leave it (422 widens it).
CREATE TABLE public.email_sequence_steps (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  step_key text NOT NULL UNIQUE,
  name text NOT NULL,
  subject text NOT NULL,
  body text NOT NULL,
  is_active boolean NOT NULL DEFAULT false,
  audience_mode text NOT NULL DEFAULT 'not_activated',
  CONSTRAINT email_sequence_steps_audience_mode_check CHECK (audience_mode IN ('not_activated', 'funnel_stage'))
);

-- billing_customers as 243 leaves it (the card columns Modal's _has_card_on_file reads).
CREATE TABLE public.billing_customers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL UNIQUE REFERENCES public.organization(id) ON DELETE CASCADE,
  stripe_customer_id text UNIQUE,
  stripe_payment_method_id text,
  billing_email text,
  card_last4 text,
  card_brand text,
  status text NOT NULL DEFAULT 'active',
  auto_charge_enabled boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- billing_invoices as 243 leaves it and org_seats as 306 leaves it (446 needs both).
CREATE TABLE public.billing_invoices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  stripe_invoice_id text UNIQUE,
  period_start timestamptz NOT NULL,
  period_end timestamptz NOT NULL
);
CREATE TABLE public.org_seats (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  clerk_user_id text NOT NULL,
  clerk_membership_id text NOT NULL UNIQUE,
  seat_status text NOT NULL DEFAULT 'active',
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- The schema as it stands before 453, to prove the rollbacks leave nothing behind.
CREATE SCHEMA contract_fixture;
CREATE VIEW contract_fixture.schema_items AS
  SELECT 'relation' AS kind, c.relname || ':' || c.relkind::text AS item
    FROM pg_class c WHERE c.relnamespace = 'public'::regnamespace
  UNION ALL
  SELECT 'column', table_name || '.' || column_name || ':' || data_type || ':' || is_nullable || ':' ||
                   coalesce(column_default, '')
    FROM information_schema.columns WHERE table_schema = 'public'
  UNION ALL
  SELECT 'constraint', conrelid::regclass::text || ':' || conname || ':' || pg_get_constraintdef(oid)
    FROM pg_constraint WHERE connamespace = 'public'::regnamespace
  UNION ALL
  SELECT 'index', indexdef FROM pg_indexes WHERE schemaname = 'public'
  UNION ALL
  SELECT 'function', p.oid::regprocedure::text FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace
  UNION ALL
  SELECT 'trigger', c.relname || ':' || t.tgname
    FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
   WHERE c.relnamespace = 'public'::regnamespace AND NOT t.tgisinternal;
