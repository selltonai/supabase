-- Migration 427's contract bootstrap: what 422 needs (427 references cs_recommendations), and billing_settings to
-- prove 427 leaves it alone. Disposable database only.
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated; END IF;
END $$;
-- Supabase's default privileges: every new table and function is granted to anon and authenticated. Without these the
-- migration's revoke check would prove nothing.
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

CREATE TABLE public.organization (id text PRIMARY KEY);
INSERT INTO public.organization VALUES ('org_a'), ('org_b'), ('org_c');

-- release_1.0.0, as last re-declared by 300.
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

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

-- billing_settings as 382 leaves it, with placeholder rows (not the real seed), and a copy to compare against.
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
  ('fixture_days', 2, 'days', 'placeholder'),
  ('fixture_count', 3, 'count', 'placeholder');
CREATE SCHEMA contract_fixture;
CREATE TABLE contract_fixture.billing_settings_before AS SELECT * FROM public.billing_settings;
