-- KAN-322 FR-C8b contract for migration 409: organization_settings.timezone. Disposable database only.
DO $$
DECLARE
  got text;
  rls boolean;
BEGIN
  -- The column: text, nullable, no default; existing rows are NULL (no backfill).
  SELECT data_type || '|' || is_nullable || '|' || coalesce(column_default, 'none') INTO got
  FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'organization_settings' AND column_name = 'timezone';
  IF got IS DISTINCT FROM 'text|YES|none' THEN RAISE EXCEPTION 'timezone column: %', got; END IF;
  SELECT string_agg(organization_id || '=' || coalesce(timezone, 'null'), ',' ORDER BY organization_id) INTO got FROM public.organization_settings;
  IF got IS DISTINCT FROM 'org_a=null,org_b=null' THEN RAISE EXCEPTION 'existing rows: %', got; END IF;

  -- Row-level security stays the table's own.
  SELECT relrowsecurity INTO rls FROM pg_class WHERE oid = 'public.organization_settings'::regclass;
  IF NOT rls THEN RAISE EXCEPTION 'row-level security was turned off'; END IF;

  -- One constraint, even after the migration ran twice.
  SELECT count(*)::text INTO got FROM pg_constraint WHERE conname = 'organization_settings_timezone_shape';
  IF got <> '1' THEN RAISE EXCEPTION 'shape constraint count: %', got; END IF;
END $$;

-- Names the shape accepts: real IANA names, UTC, deep and signed ones, and NULL again.
UPDATE public.organization_settings SET timezone = 'Europe/Berlin' WHERE organization_id = 'org_a';
UPDATE public.organization_settings SET timezone = 'UTC' WHERE organization_id = 'org_a';
UPDATE public.organization_settings SET timezone = 'America/Argentina/Buenos_Aires' WHERE organization_id = 'org_a';
UPDATE public.organization_settings SET timezone = 'Etc/GMT+5' WHERE organization_id = 'org_a';
UPDATE public.organization_settings SET timezone = 'America/Port-au-Prince' WHERE organization_id = 'org_a';
UPDATE public.organization_settings SET timezone = NULL WHERE organization_id = 'org_a';

-- Text that cannot be a zone name is refused.
DO $$
DECLARE
  bad text;
  refused boolean;
BEGIN
  FOREACH bad IN ARRAY ARRAY['', 'Europe Berlin', 'Europe/', '/Europe/Berlin', 'x;drop table t', '1Europe/Berlin', repeat('A', 65), 'Europe//Berlin'] LOOP
    refused := false;
    BEGIN
      UPDATE public.organization_settings SET timezone = bad WHERE organization_id = 'org_b';
    EXCEPTION WHEN check_violation THEN refused := true;
    END;
    IF NOT refused THEN RAISE EXCEPTION 'accepted %', quote_literal(bad); END IF;
  END LOOP;
END $$;

-- The other columns are untouched.
DO $$
BEGIN
  IF (SELECT company_name FROM public.organization_settings WHERE organization_id = 'org_a') IS DISTINCT FROM 'Acme' THEN
    RAISE EXCEPTION 'company_name changed';
  END IF;
END $$;
