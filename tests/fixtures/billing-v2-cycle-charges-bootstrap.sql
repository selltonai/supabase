-- Migration 446's contract bootstrap: the tables 446 touches, as their own migrations leave them (only the columns
-- 446 and its contract need). Disposable database only.
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated; END IF;
END $$;
-- Supabase's default privileges: every new table is granted to anon and authenticated. Without these the
-- migration's revoke check would prove nothing.
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

-- organization with signup_source (379) and the anchor (382).
CREATE TABLE public.organization (
  id text PRIMARY KEY,
  signup_source text,
  billing_cycle_anchor date
);
INSERT INTO public.organization (id, signup_source) VALUES ('org_web', NULL), ('org_phone', 'mobile'), ('org_c', 'web');

-- release_1.0.0, as last re-declared by 300.
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- billing_invoices as 243 leaves it (the columns the ledger points at).
CREATE TABLE public.billing_invoices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  stripe_invoice_id text UNIQUE,
  period_start timestamptz NOT NULL,
  period_end timestamptz NOT NULL
);

-- org_seats as 306 leaves it.
CREATE TABLE public.org_seats (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  clerk_user_id text NOT NULL,
  clerk_membership_id text NOT NULL UNIQUE,
  user_email text,
  seat_status text NOT NULL DEFAULT 'active',
  active_since timestamptz NOT NULL DEFAULT now(),
  active_until timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO public.org_seats (organization_id, clerk_user_id, clerk_membership_id) VALUES
  ('org_web', 'user_w1', 'mem_w1'),
  ('org_phone', 'user_p1', 'mem_p1'),
  ('org_c', 'user_c1', 'mem_c1');
