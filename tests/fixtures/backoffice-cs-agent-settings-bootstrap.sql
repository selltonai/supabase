-- Migration 433's contract bootstrap: Supabase's roles and default grants (433 has no table dependency), and
-- billing_settings with placeholder rows to prove 433 leaves it alone. Disposable database only.
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
CREATE TABLE contract_fixture.billing_settings_before AS SELECT * FROM public.billing_settings;
