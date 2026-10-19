-- KAN-309 V2 contract bootstrap: what public.notifications needs before its own migrations (245, 244, 361) run.
-- Disposable database only.
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
-- 245's policies call auth.uid().
CREATE SCHEMA auth;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$ SELECT NULL::uuid $$;
CREATE TABLE public.organization (id text PRIMARY KEY);
CREATE TABLE public."user" (id text PRIMARY KEY, email text);
CREATE TABLE public.user_organizations (
  user_id text NOT NULL, organization_id text NOT NULL, role text DEFAULT 'org:member',
  PRIMARY KEY (user_id, organization_id)
);
INSERT INTO public.organization VALUES ('org_a'), ('org_b');
INSERT INTO public."user" VALUES ('user_1', 'one@example.com'), ('user_2', 'two@example.com');
INSERT INTO public.user_organizations VALUES ('user_1', 'org_a', 'org:admin'), ('user_2', 'org_a', 'org:member');
