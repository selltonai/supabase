-- Migration 433's contract. Run by tests/run-backoffice-cs-agent-settings-contract.sh on a disposable database.

-- refuses(sql, sqlstate, what): the statement must fail with exactly that error (23514 check, 23502 not null,
-- 42501 insufficient privilege or the append-only guard).
CREATE FUNCTION pg_temp.refuses(p_sql text, p_state text, p_what text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE got text;
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN others THEN got := SQLSTATE;
  END;
  IF got IS NULL THEN RAISE EXCEPTION 'accepted: %', p_what; END IF;
  IF got <> p_state THEN RAISE EXCEPTION 'refused with % instead of %: %', got, p_state, p_what; END IF;
END $$;

-- Access: the service role only, RLS on, no policies; nothing seeded; billing_settings untouched (433 applied twice).
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
      RAISE EXCEPTION 'anon/authenticated still have privileges on %', t;
    END IF;
    IF NOT has_table_privilege('service_role', t, 'SELECT') OR NOT has_table_privilege('service_role', t, 'INSERT') THEN
      RAISE EXCEPTION 'service_role cannot read or write %', t;
    END IF;
    IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = t::regclass) THEN
      RAISE EXCEPTION 'RLS is off on %', t;
    END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public'
             AND tablename IN ('cs_settings', 'cs_settings_history')) THEN
    RAISE EXCEPTION 'cs_settings or its history has a policy';
  END IF;
  FOREACH f IN ARRAY ARRAY['public.cs_settings_touch()', 'public.cs_settings_record_history()',
                           'public.cs_settings_history_append_only()'] LOOP
    IF has_function_privilege('anon', f, 'EXECUTE') OR has_function_privilege('authenticated', f, 'EXECUTE') THEN
      RAISE EXCEPTION 'anon/authenticated can execute %', f;
    END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM public.cs_settings) OR EXISTS (SELECT 1 FROM public.cs_settings_history) THEN
    RAISE EXCEPTION '433 seeded rows';
  END IF;
  IF EXISTS (SELECT * FROM public.billing_settings EXCEPT SELECT * FROM contract_fixture.billing_settings_before)
     OR EXISTS (SELECT * FROM contract_fixture.billing_settings_before EXCEPT SELECT * FROM public.billing_settings) THEN
    RAISE EXCEPTION '433 changed billing_settings';
  END IF;
END $$;

-- The columns, as the backoffice reads and writes them.
DO $$
DECLARE got text[];
BEGIN
  SELECT array_agg(column_name::text ORDER BY ordinal_position) INTO got
  FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'cs_settings';
  IF got IS DISTINCT FROM ARRAY['key', 'value', 'updated_by', 'updated_at', 'reason'] THEN
    RAISE EXCEPTION 'cs_settings columns are %', got;
  END IF;
  SELECT array_agg(column_name::text ORDER BY ordinal_position) INTO got
  FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'cs_settings_history';
  IF got IS DISTINCT FROM ARRAY['id', 'key', 'operation', 'old_value', 'value', 'updated_by', 'reason', 'changed_at'] THEN
    RAISE EXCEPTION 'cs_settings_history columns are %', got;
  END IF;
  IF (SELECT data_type FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'cs_settings' AND column_name = 'value') <> 'jsonb'
     OR (SELECT is_nullable FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'cs_settings' AND column_name = 'value') <> 'NO' THEN
    RAISE EXCEPTION 'cs_settings.value is not jsonb NOT NULL';
  END IF;
END $$;

-- A browser key is refused.
SET ROLE anon;
DO $$ BEGIN
  BEGIN
    PERFORM count(*) FROM public.cs_settings;
    RAISE EXCEPTION 'anon read cs_settings';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    PERFORM count(*) FROM public.cs_settings_history;
    RAISE EXCEPTION 'anon read cs_settings_history';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SET ROLE authenticated;
DO $$ BEGIN
  BEGIN
    INSERT INTO public.cs_settings (key, value, updated_by) VALUES ('cs_llm_daily_usd_cap', '50', 'x@sellton.test');
    RAISE EXCEPTION 'authenticated wrote cs_settings';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;

-- The service role, as the backoffice: the checks, then a save, a change through PostgREST's upsert, a delete.
SET ROLE service_role;
DO $$
DECLARE
  first_at timestamptz;
  h record;
BEGIN
  PERFORM pg_temp.refuses($q$INSERT INTO public.cs_settings (key, value, updated_by) VALUES ('Bad-Key', '1', 'a@sellton.test')$q$,
    '23514', 'a key with capitals');
  PERFORM pg_temp.refuses($q$INSERT INTO public.cs_settings (key, value, updated_by) VALUES ('9cap', '1', 'a@sellton.test')$q$,
    '23514', 'a key starting with a digit');
  PERFORM pg_temp.refuses(format($q$INSERT INTO public.cs_settings (key, value, updated_by) VALUES (%L, '1', 'a@sellton.test')$q$,
    'a' || repeat('b', 80)), '23514', 'an 81-character key');
  PERFORM pg_temp.refuses($q$INSERT INTO public.cs_settings (key, value, updated_by) VALUES ('some_flag', NULL, 'a@sellton.test')$q$,
    '23502', 'a NULL value');
  PERFORM pg_temp.refuses($q$INSERT INTO public.cs_settings (key, value, updated_by) VALUES ('some_flag', 'true', NULL)$q$,
    '23502', 'no updated_by');
  PERFORM pg_temp.refuses($q$INSERT INTO public.cs_settings (key, value, updated_by) VALUES ('some_flag', 'true', '  ')$q$,
    '23514', 'a blank updated_by');
  PERFORM pg_temp.refuses($q$INSERT INTO public.cs_settings (key, value, updated_by) VALUES ('cs_llm_daily_usd_cap', '0.5', 'a@sellton.test')$q$,
    '23514', 'a cap under 1 USD');
  PERFORM pg_temp.refuses($q$INSERT INTO public.cs_settings (key, value, updated_by) VALUES ('cs_llm_daily_usd_cap', '500.01', 'a@sellton.test')$q$,
    '23514', 'a cap over 500 USD');
  PERFORM pg_temp.refuses($q$INSERT INTO public.cs_settings (key, value, updated_by) VALUES ('cs_llm_daily_usd_cap', '"50"', 'a@sellton.test')$q$,
    '23514', 'a cap that is a string');
  IF EXISTS (SELECT 1 FROM public.cs_settings) OR EXISTS (SELECT 1 FROM public.cs_settings_history) THEN
    RAISE EXCEPTION 'a refused write left a row';
  END IF;

  -- The edges are accepted; an unknown key takes any jsonb.
  INSERT INTO public.cs_settings (key, value, updated_by, reason, updated_at)
  VALUES ('cs_llm_daily_usd_cap', '1', 'owner@sellton.test', 'start low', '2000-01-01T00:00:00Z');
  SELECT updated_at INTO first_at FROM public.cs_settings WHERE key = 'cs_llm_daily_usd_cap';
  IF first_at <> now() THEN RAISE EXCEPTION 'updated_at is not the database''s (%)', first_at; END IF;
  INSERT INTO public.cs_settings (key, value, updated_by) VALUES ('some_flag', '{"on": true}', 'owner@sellton.test');

  -- PostgREST's upsert (on_conflict=key, merge-duplicates): an update, kept with the old value.
  INSERT INTO public.cs_settings (key, value, updated_by, reason)
  VALUES ('cs_llm_daily_usd_cap', '500', 'other@sellton.test', 'launch week')
  ON CONFLICT (key) DO UPDATE
    SET value = EXCLUDED.value, updated_by = EXCLUDED.updated_by, reason = EXCLUDED.reason;
  IF (SELECT value FROM public.cs_settings WHERE key = 'cs_llm_daily_usd_cap') <> '500'::jsonb THEN
    RAISE EXCEPTION 'the upsert did not change the cap';
  END IF;
  PERFORM pg_temp.refuses($q$UPDATE public.cs_settings SET value = '501' WHERE key = 'cs_llm_daily_usd_cap'$q$,
    '23514', 'an update over 500 USD');

  DELETE FROM public.cs_settings WHERE key = 'some_flag';

  IF (SELECT count(*) FROM public.cs_settings_history) <> 4 THEN
    RAISE EXCEPTION 'history has % rows, expected 4', (SELECT count(*) FROM public.cs_settings_history);
  END IF;
  SELECT * INTO h FROM public.cs_settings_history WHERE key = 'cs_llm_daily_usd_cap' AND operation = 'insert';
  IF h.old_value IS NOT NULL OR h.value <> '1'::jsonb OR h.updated_by <> 'owner@sellton.test' OR h.reason <> 'start low' THEN
    RAISE EXCEPTION 'the insert''s history row is wrong: %', row_to_json(h);
  END IF;
  SELECT * INTO h FROM public.cs_settings_history WHERE key = 'cs_llm_daily_usd_cap' AND operation = 'update';
  IF h.old_value <> '1'::jsonb OR h.value <> '500'::jsonb OR h.updated_by <> 'other@sellton.test' OR h.reason <> 'launch week' THEN
    RAISE EXCEPTION 'the update''s history row is wrong: %', row_to_json(h);
  END IF;
  SELECT * INTO h FROM public.cs_settings_history WHERE key = 'some_flag' AND operation = 'delete';
  IF h.old_value <> '{"on": true}'::jsonb OR h.value IS NOT NULL OR h.updated_by <> 'owner@sellton.test' THEN
    RAISE EXCEPTION 'the delete''s history row is wrong: %', row_to_json(h);
  END IF;

  -- History is append-only, even for the service role.
  PERFORM pg_temp.refuses($q$UPDATE public.cs_settings_history SET reason = 'rewritten'$q$, '42501', 'a history update');
  PERFORM pg_temp.refuses($q$DELETE FROM public.cs_settings_history$q$, '42501', 'a history delete');
  PERFORM pg_temp.refuses($q$TRUNCATE public.cs_settings_history$q$, '42501', 'a history truncate');
  PERFORM pg_temp.refuses($q$INSERT INTO public.cs_settings_history (id, key, operation, updated_by) VALUES (1, 'x', 'insert', 'a')$q$,
    '428C9', 'a written history id');
END $$;
RESET ROLE;

-- The contract's own rows go, so the rollback check sees a used database. History rows stay (append-only).
DELETE FROM public.cs_settings;

DO $$ BEGIN
  IF EXISTS (SELECT * FROM public.billing_settings EXCEPT SELECT * FROM contract_fixture.billing_settings_before)
     OR EXISTS (SELECT * FROM contract_fixture.billing_settings_before EXCEPT SELECT * FROM public.billing_settings) THEN
    RAISE EXCEPTION 'billing_settings changed';
  END IF;
END $$;

SELECT 'cs_settings contract: passed' AS result;
