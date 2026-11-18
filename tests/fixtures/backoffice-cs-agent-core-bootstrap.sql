-- Migration 422's contract bootstrap: only what 422 touches. Disposable database only.
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

-- email_sequence_steps as 340 and 344 leave it, with one row of each existing audience.
CREATE TABLE public.email_sequence_steps (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  step_key text NOT NULL UNIQUE,
  name text NOT NULL,
  position integer NOT NULL DEFAULT 0,
  from_status text NOT NULL DEFAULT 'pending',
  excluded_to_statuses text[] NOT NULL DEFAULT ARRAY['approved','launched','kb_built']::text[],
  delay_hours numeric NOT NULL DEFAULT 24 CHECK (delay_hours >= 0),
  subject text NOT NULL,
  body text NOT NULL,
  is_active boolean NOT NULL DEFAULT false,
  stop_when_payment_required boolean NOT NULL DEFAULT true,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_by text,
  updated_by text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  audience_mode text NOT NULL DEFAULT 'not_activated',
  CONSTRAINT email_sequence_steps_audience_mode_check CHECK (audience_mode IN ('not_activated', 'funnel_stage'))
);
INSERT INTO public.email_sequence_steps (step_key, name, subject, body, is_active, audience_mode) VALUES
  ('pending-24h', 'Pending setup after 24h', 'Can I help?', 'Hi', true, 'not_activated'),
  ('funnel-72h', 'Funnel stage after 72h', 'Still there?', 'Hi', true, 'funnel_stage');
