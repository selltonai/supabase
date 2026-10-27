-- ============================================================
-- Migration: usage-idempotency-and-batch-write (stage: next-release/395; renumber at promotion)
-- Date:      2026-10-14
-- Purpose:   KAN-333 task 2 (X1). The mobile service sends its usage to Modal's POST /billing/usage/record, one row per
--            play, service, model and hour, and retries until every row answers created or duplicate.
--              1. usage_idempotency_keys - one row per idempotency_key, pointing at the usage row it wrote. A table of its
--                 own, not a unique column on usage: once usage is split by month its unique indexes must include
--                 created_at, and a retry gets a new created_at, so a unique usage column would stop catching retries.
--              2. record_usage_batch_v1(p_rows jsonb) - writes a batch Modal has already validated and priced, in one
--                 transaction, answering created or duplicate per row in the order sent.
-- Projects:  selltonai-database/supabase (owner); caller: selltonai-modal UsageService.record_usage_batch (service role).
--            The web and the backoffice are unaffected: their usage writes do not go through this function.
-- Contract:  New table and new function only. Each p_rows element uses usage's column names plus idempotency_key;
--            usage_context is always 'mobile'. Rows insert through usage's existing triggers (summary, 345 projection).
-- Rollback:  migrations/next-release/rollback/395_usage-idempotency-and-batch-write.rollback.sql
-- ============================================================

CREATE TABLE IF NOT EXISTS public.usage_idempotency_keys (
  idempotency_key text PRIMARY KEY CHECK (char_length(idempotency_key) BETWEEN 8 AND 200),
  usage_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.usage_idempotency_keys IS
  'KAN-333 X1: the idempotency key of every usage row written by record_usage_batch_v1 and the usage id it wrote. '
  'Pruned after 14 months once usage is split by month (not yet).';

ALTER TABLE public.usage_idempotency_keys ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.usage_idempotency_keys FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT ON TABLE public.usage_idempotency_keys TO service_role;

CREATE OR REPLACE FUNCTION public.record_usage_batch_v1(p_rows jsonb)
RETURNS TABLE (row_key text, row_status text, row_usage_id uuid)
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, pg_temp
AS $$
DECLARE
  r jsonb;
  v_key text;
  v_new uuid;
  v_inserted uuid;
BEGIN
  IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' THEN
    RAISE EXCEPTION 'record_usage_batch_v1: p_rows must be a JSON array' USING ERRCODE = '22023';
  END IF;

  FOR r IN SELECT e.value FROM jsonb_array_elements(p_rows) AS e(value) LOOP
    v_key := r->>'idempotency_key';
    IF v_key IS NULL THEN
      RAISE EXCEPTION 'record_usage_batch_v1: a row has no idempotency_key' USING ERRCODE = '22023';
    END IF;
    v_new := gen_random_uuid();
    v_inserted := NULL;

    INSERT INTO public.usage_idempotency_keys (idempotency_key, usage_id)
    VALUES (v_key, v_new)
    ON CONFLICT (idempotency_key) DO NOTHING
    RETURNING usage_id INTO v_inserted;

    IF v_inserted IS NOT NULL THEN
      INSERT INTO public.usage (
        id, organization_id, user_id, campaign_id, session_id, provider, model_name, api_calls,
        input_tokens, output_tokens, total_tokens, description, tracking_start, tracking_end, metadata, usage_context,
        original_pricing, sellton_pricing, original_cost, sellton_cost
      ) VALUES (
        v_new, r->>'organization_id', NULLIF(r->>'user_id', ''), NULLIF(r->>'campaign_id', ''), r->>'session_id',
        r->>'provider', r->>'model_name', (r->>'api_calls')::int, (r->>'input_tokens')::int,
        (r->>'output_tokens')::int, (r->>'total_tokens')::int, r->>'description', (r->>'tracking_start')::timestamptz,
        (r->>'tracking_end')::timestamptz, COALESCE(r->'metadata', '{}'::jsonb), 'mobile',
        COALESCE(r->'original_pricing', '{}'::jsonb), COALESCE(r->'sellton_pricing', '{}'::jsonb),
        (r->>'original_cost')::numeric, (r->>'sellton_cost')::numeric
      );
      row_key := v_key; row_status := 'created'; row_usage_id := v_new;
    ELSE
      -- A concurrent batch with the same key waited on the primary key above and committed first.
      SELECT k.usage_id INTO row_usage_id FROM public.usage_idempotency_keys k WHERE k.idempotency_key = v_key;
      row_key := v_key; row_status := 'duplicate';
    END IF;
    RETURN NEXT;
  END LOOP;
END;
$$;

COMMENT ON FUNCTION public.record_usage_batch_v1(jsonb) IS
  'KAN-333 X1: writes a batch of usage rows Modal has validated and priced, once per idempotency_key, in one '
  'transaction. Answers (row_key, row_status created|duplicate, row_usage_id) per row, in the order sent.';

REVOKE ALL ON FUNCTION public.record_usage_batch_v1(jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_usage_batch_v1(jsonb) TO service_role;

-- Verify (read-only):
--   SELECT has_table_privilege('anon', 'public.usage_idempotency_keys', 'SELECT'),
--          has_function_privilege('anon', 'public.record_usage_batch_v1(jsonb)', 'EXECUTE'),
--          has_function_privilege('authenticated', 'public.record_usage_batch_v1(jsonb)', 'EXECUTE'),
--          has_function_privilege('service_role', 'public.record_usage_batch_v1(jsonb)', 'EXECUTE');  -- f, f, f, t
--   SELECT count(*) FROM public.usage_idempotency_keys k LEFT JOIN public.usage u ON u.id = k.usage_id WHERE u.id IS NULL;  -- 0
