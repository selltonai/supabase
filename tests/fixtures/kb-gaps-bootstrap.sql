-- KB gaps contract bootstrap (448): only what migration 448 touches. Disposable database only.
DO $$ BEGIN
  -- Supabase's service_role bypasses RLS; the contract calls as it.
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role BYPASSRLS; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated; END IF;
END $$;
-- Supabase's default privileges: every new table and function is granted to anon and authenticated. Without these the
-- migration's revoke check would prove nothing.
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

-- release_1.0.0, as last re-declared by 300.
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE TABLE public.organization (id text PRIMARY KEY);
INSERT INTO public.organization VALUES ('org_a'), ('org_b'), ('org_gone');

CREATE TABLE public.campaigns (
  id uuid PRIMARY KEY,
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE
);
INSERT INTO public.campaigns VALUES
  ('11111111-1111-1111-1111-111111111111', 'org_a'),
  ('22222222-2222-2222-2222-222222222222', 'org_b');

CREATE TABLE public.organization_files (
  id uuid PRIMARY KEY,
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE
);
INSERT INTO public.organization_files VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'org_a'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'org_b'),
  ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'org_a');
