-- Migration 429's contract bootstrap: organization (429's only dependency), and usage and billing_settings to prove
-- 429 leaves them alone. Disposable database only.
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated; END IF;
END $$;
-- Supabase's service role bypasses RLS; the contract writes as it, the way the backoffice does.
ALTER ROLE service_role BYPASSRLS;
-- Supabase's default privileges: every new table and function is granted to anon and authenticated. Without these the
-- migration's revoke check would prove nothing.
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

CREATE TABLE public.organization (id text PRIMARY KEY, name text);
INSERT INTO public.organization VALUES ('org_a', 'Fixture A'), ('org_b', 'Fixture B'), ('org_c', 'Fixture C');

-- usage as release_1.0.5/1 and 123 leave it (the columns the backoffice reads), with placeholder rows.
CREATE TABLE public.usage (
  id bigserial PRIMARY KEY,
  organization_id text NOT NULL,
  user_id text,
  original_cost numeric(12,6) DEFAULT 0,
  sellton_cost numeric(12,6) DEFAULT 0,
  created_at timestamptz DEFAULT now()
);
INSERT INTO public.usage (organization_id, user_id, original_cost, sellton_cost) VALUES
  ('org_a', 'user_1', 1.000000, 2.000000),
  ('org_b', NULL, 0.500000, 0.750000);

-- billing_settings as 382 leaves it, with placeholder rows (not the real seed).
CREATE TABLE public.billing_settings (
  key         text PRIMARY KEY,
  value       numeric(12,2) NOT NULL CHECK (value >= 0),
  unit        text NOT NULL CHECK (unit IN ('usd', 'days', 'count')),
  description text,
  updated_by  text,
  updated_at  timestamptz NOT NULL DEFAULT now()
);
INSERT INTO public.billing_settings (key, value, unit, description) VALUES
  ('fixture_price_usd', 1.00, 'usd', 'placeholder'),
  ('fixture_count', 3, 'count', 'placeholder');

CREATE SCHEMA contract_fixture;
CREATE TABLE contract_fixture.usage_before AS SELECT * FROM public.usage;
CREATE TABLE contract_fixture.billing_settings_before AS SELECT * FROM public.billing_settings;
