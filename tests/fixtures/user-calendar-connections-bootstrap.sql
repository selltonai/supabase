-- KAN-309 contract bootstrap: only what migration 404 touches. Disposable database only.
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role BYPASSRLS; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated; END IF;
END $$;
-- Supabase's default privileges: every new table and function is granted to anon and authenticated. Without these the
-- migration's revoke check would prove nothing.
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
CREATE TABLE public.organization (id text PRIMARY KEY);
CREATE TABLE public."user" (id text PRIMARY KEY, email text);
INSERT INTO public.organization VALUES ('org_a'), ('org_b');
INSERT INTO public."user" VALUES ('user_1', 'one@example.com'), ('user_2', 'two@example.com');
