-- Disposable fixture for the real billing migrations; never a deployed schema.
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN BYPASSRLS;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role;
CREATE TABLE public.organization (id text PRIMARY KEY, name text);
CREATE TABLE public.usage (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), organization_id text, created_at timestamptz DEFAULT now());
CREATE TABLE public.discount_codes (code text PRIMARY KEY);
CREATE OR REPLACE FUNCTION public.update_updated_at_column() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at := now(); RETURN NEW; END $$;
-- Matches the audit table in migration 341.
CREATE TABLE public.backoffice_audit_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), actor text NOT NULL, action text NOT NULL,
  organization_id text REFERENCES public.organization(id) ON DELETE SET NULL,
  resource_type text, resource_id text, payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
