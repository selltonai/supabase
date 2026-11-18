-- ============================================================
-- Migration: 433_backoffice-cs-agent-settings (stage: next-release/433; renumber at promotion if 433 is taken)
-- Date:      2026-11-11
-- Purpose:   The backoffice's customer-success agent, its runtime settings: values a super admin changes from the
--            backoffice (/cs/settings) without a code change or a deploy. The first is the daily model spend cap.
--            1. cs_settings: one row per key, its jsonb value, who set it, when and why.
--            2. cs_settings_history: every insert, update and delete of a cs_settings row, written by a trigger,
--               append-only (updates and deletes of history rows are refused).
-- Projects:  selltonai-database/supabase (owner). backoffice is the only writer (a super admin's form) and the only
--            reader (the agent's model client, every 60 seconds). selltonai-modal, selltonai, the mobile service and
--            the engine: none.
-- Contract:  Additive. Two new tables and two trigger functions; no other object changes. Service role only: RLS on
--            with no policies, and anon and authenticated get no table or function privileges.
--            key matches ^[a-z][a-z0-9_]{0,79}$. value is any jsonb, NOT NULL; the known key cs_llm_daily_usd_cap
--            must be a JSON number from 1 to 500 (USD per UTC day). updated_by (the person's email) is required;
--            updated_at is set by the database on every write; reason is free text.
--            No row is seeded: without a row the backoffice uses its environment (CS_LLM_DAILY_USD_CAP), so this file
--            changes no behaviour until a super admin saves a value. The backoffice treats a missing table as "not
--            deployed" and uses the environment, so this file and the backoffice build ship in either order.
--            Application code: none must ship together with this file.
-- Depends:   nothing.
-- Rollback:  rollback/433_backoffice-cs-agent-settings.rollback.sql
--
-- Keys:
--   cs_llm_daily_usd_cap  number, 1..500: the agent's model spend cap per UTC day, in USD. Overrides the environment.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.cs_settings (
  key text PRIMARY KEY CONSTRAINT cs_settings_key_format CHECK (key ~ '^[a-z][a-z0-9_]{0,79}$'),
  value jsonb NOT NULL,
  updated_by text NOT NULL CONSTRAINT cs_settings_updated_by_check
    CHECK (char_length(btrim(updated_by)) BETWEEN 1 AND 320),
  updated_at timestamptz NOT NULL DEFAULT now(),
  reason text CONSTRAINT cs_settings_reason_check CHECK (reason IS NULL OR char_length(reason) <= 2000),
  -- The known keys' shapes. A key not listed here takes any jsonb value.
  CONSTRAINT cs_settings_known_values CHECK (
    CASE
      WHEN key <> 'cs_llm_daily_usd_cap' THEN true
      WHEN jsonb_typeof(value) <> 'number' THEN false
      ELSE (value #>> '{}')::numeric BETWEEN 1 AND 500
    END
  )
);

CREATE TABLE IF NOT EXISTS public.cs_settings_history (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  key text NOT NULL CONSTRAINT cs_settings_history_key_format CHECK (key ~ '^[a-z][a-z0-9_]{0,79}$'),
  operation text NOT NULL CONSTRAINT cs_settings_history_operation_check
    CHECK (operation IN ('insert', 'update', 'delete')),
  -- NULL on insert.
  old_value jsonb,
  -- NULL on delete.
  value jsonb,
  -- The row's updated_by after the change (before it, for a delete).
  updated_by text NOT NULL,
  reason text,
  changed_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS cs_settings_history_key_idx
  ON public.cs_settings_history (key, changed_at DESC, id DESC);

-- updated_at is the database's, on every write.
CREATE OR REPLACE FUNCTION public.cs_settings_touch()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END $$;

-- Every change becomes a history row.
CREATE OR REPLACE FUNCTION public.cs_settings_record_history()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.cs_settings_history (key, operation, old_value, value, updated_by, reason)
    VALUES (NEW.key, 'insert', NULL, NEW.value, NEW.updated_by, NEW.reason);
    RETURN NEW;
  ELSIF TG_OP = 'UPDATE' THEN
    INSERT INTO public.cs_settings_history (key, operation, old_value, value, updated_by, reason)
    VALUES (NEW.key, 'update', OLD.value, NEW.value, NEW.updated_by, NEW.reason);
    RETURN NEW;
  END IF;
  INSERT INTO public.cs_settings_history (key, operation, old_value, value, updated_by, reason)
  VALUES (OLD.key, 'delete', OLD.value, NULL, OLD.updated_by, OLD.reason);
  RETURN OLD;
END $$;

-- History is append-only.
CREATE OR REPLACE FUNCTION public.cs_settings_history_append_only()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  RAISE EXCEPTION 'cs_settings_history is append-only (% refused)', TG_OP
    USING ERRCODE = 'insufficient_privilege';
END $$;

DROP TRIGGER IF EXISTS cs_settings_touch ON public.cs_settings;
CREATE TRIGGER cs_settings_touch
  BEFORE INSERT OR UPDATE ON public.cs_settings
  FOR EACH ROW EXECUTE FUNCTION public.cs_settings_touch();

DROP TRIGGER IF EXISTS cs_settings_record_history ON public.cs_settings;
CREATE TRIGGER cs_settings_record_history
  AFTER INSERT OR UPDATE OR DELETE ON public.cs_settings
  FOR EACH ROW EXECUTE FUNCTION public.cs_settings_record_history();

DROP TRIGGER IF EXISTS cs_settings_history_append_only ON public.cs_settings_history;
CREATE TRIGGER cs_settings_history_append_only
  BEFORE UPDATE OR DELETE ON public.cs_settings_history
  FOR EACH ROW EXECUTE FUNCTION public.cs_settings_history_append_only();

DROP TRIGGER IF EXISTS cs_settings_history_no_truncate ON public.cs_settings_history;
CREATE TRIGGER cs_settings_history_no_truncate
  BEFORE TRUNCATE ON public.cs_settings_history
  FOR EACH STATEMENT EXECUTE FUNCTION public.cs_settings_history_append_only();

-- Access: the service role only ----------------------------------------------------------------------
-- Supabase grants new tables and functions to anon and authenticated by default; take that away. RLS is on with no
-- policies on purpose: the backoffice reads and writes with the service role, and browser keys see nothing.

REVOKE ALL ON TABLE public.cs_settings FROM PUBLIC, anon, authenticated;
REVOKE ALL ON TABLE public.cs_settings_history FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.cs_settings TO service_role;
GRANT ALL ON TABLE public.cs_settings_history TO service_role;

REVOKE ALL ON FUNCTION public.cs_settings_touch() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.cs_settings_record_history() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.cs_settings_history_append_only() FROM PUBLIC, anon, authenticated;

ALTER TABLE public.cs_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cs_settings_history ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.cs_settings IS
  'Backoffice customer-success agent: runtime settings a super admin changes from the backoffice (/cs/settings), one row per key (^[a-z][a-z0-9_]{0,79}$) with a jsonb value, who set it (updated_by), when (updated_at, set by the database) and why. cs_llm_daily_usd_cap: a number 1..500, the model spend cap per UTC day in USD, over the environment. Nothing seeded. Every change is kept in cs_settings_history. Backoffice only.';
COMMENT ON TABLE public.cs_settings_history IS
  'Backoffice customer-success agent: every insert, update and delete of a cs_settings row (old and new value, who, why, when), written by a trigger. Append-only: updates, deletes and truncate are refused. Backoffice only.';

-- Fail the file if a browser key can still reach a table or a function.
DO $$
DECLARE
  t text;
  f text;
BEGIN
  FOREACH t IN ARRAY ARRAY['public.cs_settings', 'public.cs_settings_history'] LOOP
    IF has_table_privilege('anon', t, 'SELECT') OR has_table_privilege('authenticated', t, 'SELECT')
       OR has_table_privilege('anon', t, 'INSERT') OR has_table_privilege('authenticated', t, 'INSERT')
       OR has_table_privilege('anon', t, 'UPDATE') OR has_table_privilege('authenticated', t, 'UPDATE')
       OR has_table_privilege('anon', t, 'DELETE') OR has_table_privilege('authenticated', t, 'DELETE') THEN
      RAISE EXCEPTION '433: anon or authenticated can still read or write %', t;
    END IF;
  END LOOP;
  FOREACH f IN ARRAY ARRAY['public.cs_settings_touch()', 'public.cs_settings_record_history()',
                           'public.cs_settings_history_append_only()'] LOOP
    IF has_function_privilege('anon', f, 'EXECUTE') OR has_function_privilege('authenticated', f, 'EXECUTE') THEN
      RAISE EXCEPTION '433: anon or authenticated can still execute %', f;
    END IF;
  END LOOP;
END $$;

-- Verify (read-only):
-- select relname, relrowsecurity from pg_class where relname in ('cs_settings', 'cs_settings_history');
--   -> both true
-- select count(*) from pg_policies where tablename in ('cs_settings', 'cs_settings_history');
--   -> 0
-- select has_table_privilege('anon', 'public.cs_settings', 'SELECT'),            -- false
--        has_table_privilege('service_role', 'public.cs_settings', 'INSERT');    -- true
-- select count(*) from public.cs_settings;                                       -- 0 (nothing seeded)
