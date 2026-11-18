-- Migration 440's fixture: production's state after main's release_1.3.0/374 (2026-10-27), on a disposable database.
-- Supabase's roles, the three rollup functions (stub bodies, real signatures) and billing_week_snapshot with 374's
-- grants: the 5-argument function and the table open to authenticated; _v2 and _v3 closed by 390.
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role NOLOGIN BYPASSRLS; END IF;
END $$;
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

CREATE TABLE IF NOT EXISTS public.billing_week_snapshot (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL,
  week_start date NOT NULL,
  week_end date NOT NULL,
  line_items jsonb NOT NULL DEFAULT '[]'::jsonb,
  total_sellton_cost numeric NOT NULL DEFAULT 0,
  generated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, week_start)
);
INSERT INTO public.billing_week_snapshot (organization_id, week_start, week_end)
VALUES ('org_a', '2026-11-09', '2026-11-15') ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION public.analytics_usage_rollup(
  p_organization_id text, p_from timestamptz, p_to timestamptz, p_group_by text, p_filter text
) RETURNS TABLE (organization_id text, total numeric)
LANGUAGE sql SECURITY DEFINER SET search_path = public
AS $$ SELECT p_organization_id, 0::numeric $$;

CREATE OR REPLACE FUNCTION public.analytics_usage_rollup_v2(p_organization_id text)
RETURNS numeric LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$ SELECT 0::numeric $$;
CREATE OR REPLACE FUNCTION public.analytics_usage_rollup_v3(p_organization_id text)
RETURNS numeric LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$ SELECT 0::numeric $$;

-- 374's grants (PUBLIC keeps its default EXECUTE on the 5-argument function, as on production).
GRANT EXECUTE ON FUNCTION public.analytics_usage_rollup(text, timestamptz, timestamptz, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.analytics_usage_rollup(text, timestamptz, timestamptz, text, text) TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.billing_week_snapshot TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.billing_week_snapshot TO service_role;
-- 390's treatment of _v2 and _v3.
REVOKE ALL ON FUNCTION public.analytics_usage_rollup_v2(text), public.analytics_usage_rollup_v3(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.analytics_usage_rollup_v2(text), public.analytics_usage_rollup_v3(text) TO service_role;

-- The hole is there before 440 (otherwise the contract proves nothing).
DO $$ BEGIN
  IF NOT has_function_privilege('authenticated', 'public.analytics_usage_rollup(text, timestamptz, timestamptz, text, text)', 'EXECUTE')
     OR NOT has_function_privilege('anon', 'public.analytics_usage_rollup(text, timestamptz, timestamptz, text, text)', 'EXECUTE')
     OR NOT has_table_privilege('authenticated', 'public.billing_week_snapshot', 'SELECT') THEN
    RAISE EXCEPTION 'fixture: expected 374''s open grants before 440';
  END IF;
END $$;
