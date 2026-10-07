-- S10 / migration 390 contract bootstrap. Disposable database only.
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated; END IF;
END $$;

-- As on the Supabase image: new functions in public are granted to anon and authenticated, and PUBLIC keeps its
-- default EXECUTE. Without this the grant checks below would prove nothing. service_role is left out on purpose
-- (as in the 388 bootstrap): it reaches the functions only through PUBLIC, so the migration's own GRANT to
-- service_role is what keeps the app working, and the contract sees it.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon, authenticated;
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

-- Stand-ins with the production signatures (bodies do not matter for grants).
CREATE FUNCTION public.claim_due_sequence_actions(p_now timestamptz, p_lease timestamptz, p_limit integer)
RETURNS integer LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$ SELECT p_limit $$;
CREATE FUNCTION public.delete_organization_file_fast(p_file_id uuid, p_org text)
RETURNS boolean LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$ SELECT true $$;
CREATE FUNCTION public.get_organization_summary(p_org text)
RETURNS integer LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$ SELECT 1 $$;
-- Two overloads of one name: both must be revoked.
CREATE FUNCTION public.analytics_usage_rollup(p_org text, p_from timestamptz, p_to timestamptz, p_a text, p_b text)
RETURNS integer LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$ SELECT 1 $$;
CREATE FUNCTION public.analytics_usage_rollup(p_org text)
RETURNS integer LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$ SELECT 2 $$;
-- 317's shape: revoked from PUBLIC only, so Supabase's direct anon/authenticated default grants remain.
CREATE FUNCTION public.reserve_billing_invoice_number(p_year integer, p_prefix text, p_start integer, p_org text)
RETURNS text LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$ SELECT p_prefix $$;
REVOKE ALL ON FUNCTION public.reserve_billing_invoice_number(integer, text, integer, text) FROM PUBLIC;
-- A non-definer one on the list.
CREATE FUNCTION public.usage_analytics_projection_contribution(p_value integer)
RETURNS integer LANGUAGE sql AS $$ SELECT p_value $$;
-- analytics_usage_rollup_v2, the deal triggers and the rest are deliberately ABSENT: the migration must skip them.

-- A trigger function on the list, with its trigger: it must still fire after the revoke.
CREATE TABLE public.organization_files (id serial PRIMARY KEY, name text);
CREATE TABLE public.file_upload_log (file_id integer);
CREATE FUNCTION public.log_file_upload() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN INSERT INTO public.file_upload_log VALUES (NEW.id); RETURN NEW; END $$;
CREATE TRIGGER trg_log_file_upload AFTER INSERT ON public.organization_files FOR EACH ROW EXECUTE FUNCTION public.log_file_upload();
GRANT INSERT, SELECT ON public.organization_files TO service_role;
GRANT USAGE ON SEQUENCE public.organization_files_id_seq TO service_role;

-- NOT on the list: must keep its grants (the migration is a list, not a blanket revoke).
CREATE FUNCTION public.keep_public_helper() RETURNS integer LANGUAGE sql AS $$ SELECT 42 $$;
