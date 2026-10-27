-- Migration: 389_remove_sellton_brain_database_webhooks
-- Purpose: Remove the retired Supabase → Sellton Brain company/contact sync hooks.
-- Projects: sellton-brain now reads the data through its own ingestion feature.
-- Contract: No application schema or API contract changes.

-- Dashboard-created Database Webhooks are ordinary triggers invoking
-- supabase_functions.http_request. Match both the source tables and the
-- retired Brain endpoints so unrelated webhooks on these tables are preserved.
DO $$
DECLARE
  webhook_trigger record;
  trigger_url text;
BEGIN
  FOR webhook_trigger IN
    SELECT
      trigger_relation.oid AS relation_id,
      trigger_relation.relname AS relation_name,
      trigger_row.tgname AS trigger_name,
      trigger_row.tgargs AS trigger_arguments
    FROM pg_trigger AS trigger_row
    JOIN pg_class AS trigger_relation ON trigger_relation.oid = trigger_row.tgrelid
    JOIN pg_namespace AS trigger_namespace ON trigger_namespace.oid = trigger_relation.relnamespace
    JOIN pg_proc AS trigger_function ON trigger_function.oid = trigger_row.tgfoid
    JOIN pg_namespace AS function_namespace ON function_namespace.oid = trigger_function.pronamespace
    WHERE NOT trigger_row.tgisinternal
      AND trigger_namespace.nspname = 'public'
      AND trigger_relation.relname IN ('companies', 'contacts')
      AND function_namespace.nspname = 'supabase_functions'
      AND trigger_function.proname = 'http_request'
  LOOP
    trigger_url := convert_from(
      substring(
        webhook_trigger.trigger_arguments
        FROM 1 FOR position(decode('00', 'hex') IN webhook_trigger.trigger_arguments) - 1
      ),
      'UTF8'
    );

    IF trigger_url ~* '^https?://[^/]+/sync/(company|contact)/?$' THEN
      EXECUTE format(
        'DROP TRIGGER %I ON %s',
        webhook_trigger.trigger_name,
        webhook_trigger.relation_id::regclass
      );
      RAISE NOTICE 'Removed retired Sellton Brain webhook trigger % on public.%',
        webhook_trigger.trigger_name,
        webhook_trigger.relation_name;
    END IF;
  END LOOP;
END;
$$;
