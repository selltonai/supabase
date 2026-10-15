-- KAN-333 X1 contract for 394 to 397. Disposable database only (tests/run-mobile-usage-x1-contract.sh).
-- The transaction rolls back every fixture row.
BEGIN;
SET LOCAL TIME ZONE 'UTC';
UPDATE public.usage_analytics_projection_state SET historical_backfill_completed_at = now() WHERE singleton;

-- 394. The browser's roles reach none of the three tables, their sequences or the views over usage; service_role does.
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['public.usage', 'public.usage_summary', 'public.action_label_map', 'public.usage_cost_daily'] LOOP
    IF has_table_privilege('anon', t, 'SELECT') OR has_table_privilege('authenticated', t, 'SELECT')
       OR has_table_privilege('anon', t, 'INSERT') OR has_table_privilege('anon', t, 'UPDATE') OR has_table_privilege('anon', t, 'DELETE')
       OR has_table_privilege('authenticated', t, 'INSERT') OR has_table_privilege('authenticated', t, 'DELETE') THEN
      RAISE EXCEPTION '394: % is still open to anon or authenticated', t;
    END IF;
    IF NOT has_table_privilege('service_role', t, 'SELECT') THEN RAISE EXCEPTION '394: service_role lost %', t; END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename IN ('usage', 'usage_summary')) THEN
    RAISE EXCEPTION '394: an allow-all policy survived';
  END IF;
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.usage'::regclass) THEN RAISE EXCEPTION '394: RLS is off on usage'; END IF;
END $$;

INSERT INTO public.usage (organization_id, session_id, provider, sellton_cost) VALUES ('org-z', 'z', 'openai', 1);
SET LOCAL ROLE anon;
DO $$
BEGIN
  BEGIN PERFORM 1 FROM public.usage LIMIT 1; RAISE EXCEPTION '394: anon read usage';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN PERFORM 1 FROM public.usage_cost_daily LIMIT 1; RAISE EXCEPTION '394: anon read usage through a view';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN DELETE FROM public.usage; RAISE EXCEPTION '394: anon deleted usage';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN INSERT INTO public.action_label_map (task_key, display_label) VALUES ('x', 'x'); RAISE EXCEPTION '394: anon wrote action_label_map';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SET LOCAL ROLE service_role;
DO $$
BEGIN
  IF (SELECT count(*) FROM public.usage WHERE organization_id = 'org-z') <> 1 THEN RAISE EXCEPTION '394: service_role cannot read usage'; END IF;
END $$;
RESET ROLE;
DELETE FROM public.usage WHERE organization_id = 'org-z';

-- 395. Grants.
DO $$
BEGIN
  IF has_function_privilege('anon', 'public.record_usage_batch_v1(jsonb)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.record_usage_batch_v1(jsonb)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.record_usage_batch_v1(jsonb)', 'EXECUTE') THEN
    RAISE EXCEPTION '395: record_usage_batch_v1 must be service_role only';
  END IF;
  IF has_table_privilege('anon', 'public.usage_idempotency_keys', 'SELECT')
     OR NOT has_table_privilege('service_role', 'public.usage_idempotency_keys', 'INSERT') THEN
    RAISE EXCEPTION '395: usage_idempotency_keys grants';
  END IF;
END $$;

-- A priced phone batch, shaped as Modal sends it. Row 3 repeats row 1's key.
CREATE TEMP TABLE x1_batch AS SELECT $j$[
  {"idempotency_key": "mobile:org-x:none:mobile_email_writing:deepseek-v4-flash:20261013T14:w1", "organization_id": "org-x",
   "user_id": "user-1", "campaign_id": null, "session_id": "mobile:org-x", "provider": "deepseek", "model_name": "deepseek-v4-flash",
   "api_calls": 12, "input_tokens": 48211, "output_tokens": 3120, "total_tokens": 51331, "description": "Mobile · mobile_email_writing",
   "tracking_start": "2026-10-13T14:00:00+00:00", "tracking_end": "2026-10-13T15:00:00+00:00",
   "metadata": {"app": "mobile", "service": "mobile_email_writing", "cache_read_input_tokens": 40960},
   "original_pricing": {"model": "deepseek-v4-flash"}, "sellton_pricing": {"model": "deepseek-v4-flash"}, "original_cost": 0.004, "sellton_cost": 0.0123},
  {"idempotency_key": "mobile:org-x:none:mobile_phone_discovery:brain-phone-finder:20261013T14:w1", "organization_id": "org-x",
   "user_id": "user-1", "campaign_id": "", "session_id": "mobile:org-x", "provider": "brain", "model_name": "brain-phone-finder",
   "api_calls": 2, "input_tokens": 0, "output_tokens": 0, "total_tokens": 0, "description": "Mobile · mobile_phone_discovery",
   "tracking_start": "2026-10-13T14:00:00+00:00", "tracking_end": "2026-10-13T15:00:00+00:00",
   "metadata": {"app": "mobile", "service": "mobile_phone_discovery", "action": "phone_finder", "phones_found": 2, "billable_units": 2},
   "original_pricing": {"cost_basis": "provider_reported"}, "sellton_pricing": {"profit_multiplier": 1.5}, "original_cost": 0.01926, "sellton_cost": 0.02889},
  {"idempotency_key": "mobile:org-x:none:mobile_email_writing:deepseek-v4-flash:20261013T14:w1", "organization_id": "org-x",
   "session_id": "mobile:org-x", "provider": "deepseek", "model_name": "deepseek-v4-flash", "api_calls": 99, "input_tokens": 1,
   "output_tokens": 1, "total_tokens": 2, "metadata": {"service": "mobile_email_writing"}, "original_cost": 9, "sellton_cost": 9}
]$j$::jsonb AS rows;

CREATE TEMP TABLE x1_first AS
  SELECT o.ordinality AS n, r.row_key, r.row_status, r.row_usage_id
  FROM public.record_usage_batch_v1((SELECT rows FROM x1_batch)) WITH ORDINALITY AS o(row_key, row_status, row_usage_id, ordinality)
  JOIN LATERAL (SELECT o.row_key, o.row_status, o.row_usage_id) r ON true;

DO $$
DECLARE u public.usage;
BEGIN
  IF (SELECT string_agg(row_status, ',' ORDER BY n) FROM x1_first) <> 'created,created,duplicate' THEN
    RAISE EXCEPTION '395: first batch answered %', (SELECT string_agg(row_status, ',' ORDER BY n) FROM x1_first);
  END IF;
  IF (SELECT row_usage_id FROM x1_first WHERE n = 3) IS DISTINCT FROM (SELECT row_usage_id FROM x1_first WHERE n = 1) THEN
    RAISE EXCEPTION '395: a repeated key in one batch must answer the first row''s id';
  END IF;
  IF (SELECT count(*) FROM public.usage WHERE organization_id = 'org-x') <> 2 THEN RAISE EXCEPTION '395: expected 2 usage rows'; END IF;
  SELECT * INTO u FROM public.usage WHERE id = (SELECT row_usage_id FROM x1_first WHERE n = 1);
  IF u.usage_context <> 'mobile' OR u.api_calls <> 12 OR u.total_tokens <> 51331 OR u.sellton_cost <> 0.0123
     OR u.tracking_start <> '2026-10-13T14:00:00Z' OR u.metadata ->> 'service' <> 'mobile_email_writing' OR u.user_id <> 'user-1'
     OR u.campaign_id IS NOT NULL OR u.invoice_id IS NOT NULL OR u.description <> 'Mobile · mobile_email_writing' THEN
    RAISE EXCEPTION '395: row 1 stored wrong: %', to_jsonb(u);
  END IF;
  IF (SELECT campaign_id FROM public.usage WHERE id = (SELECT row_usage_id FROM x1_first WHERE n = 2)) IS NOT NULL THEN
    RAISE EXCEPTION '395: an empty campaign_id must be stored as NULL';
  END IF;
END $$;

-- The same batch again writes nothing and answers duplicate with the first ids.
DO $$
DECLARE again record; i int := 0;
BEGIN
  FOR again IN SELECT * FROM public.record_usage_batch_v1((SELECT rows FROM x1_batch)) LOOP
    i := i + 1;
    IF again.row_status <> 'duplicate' OR again.row_usage_id IS DISTINCT FROM (SELECT row_usage_id FROM x1_first WHERE n = i) THEN
      RAISE EXCEPTION '395: resend row % answered % %', i, again.row_status, again.row_usage_id;
    END IF;
  END LOOP;
  IF i <> 3 THEN RAISE EXCEPTION '395: resend answered % rows', i; END IF;
  IF (SELECT count(*) FROM public.usage WHERE organization_id = 'org-x') <> 2 OR (SELECT count(*) FROM public.usage_idempotency_keys) <> 2 THEN
    RAISE EXCEPTION '395: the resend wrote rows';
  END IF;
END $$;

-- A bad key fails the whole batch (Modal rejects it before), and nothing of that batch is written.
DO $$
BEGIN
  BEGIN
    PERFORM * FROM public.record_usage_batch_v1('[{"idempotency_key": "mobile:org-x:ok-key-long-enough", "organization_id": "org-x", "session_id": "s", "provider": "deepseek"},
                                                  {"idempotency_key": "short", "organization_id": "org-x", "session_id": "s", "provider": "deepseek"}]'::jsonb);
    RAISE EXCEPTION '395: a 5-character key was accepted';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  IF EXISTS (SELECT 1 FROM public.usage_idempotency_keys WHERE idempotency_key = 'mobile:org-x:ok-key-long-enough') THEN
    RAISE EXCEPTION '395: a failed batch left a row behind';
  END IF;
END $$;

-- 396. The rest of the phone's services, then a web row in the same org.
CREATE TEMP TABLE x1_more AS SELECT * FROM public.record_usage_batch_v1($j$[
  {"idempotency_key": "mobile:org-x:none:mobile_voice:eleven_multilingual_v2:20261013T14:w1", "organization_id": "org-x",
   "session_id": "mobile:org-x", "provider": "elevenlabs", "model_name": "eleven_multilingual_v2", "api_calls": 3,
   "input_tokens": 0, "output_tokens": 0, "total_tokens": 0, "metadata": {"service": "mobile_voice", "characters": 1200, "billable_units": 1200},
   "original_cost": 0, "sellton_cost": 0},
  {"idempotency_key": "mobile:org-x:none:mobile_company_search:brain-companies:20261013T14:w1", "organization_id": "org-x",
   "session_id": "mobile:org-x", "provider": "brain", "model_name": "brain-companies", "api_calls": 1,
   "input_tokens": 0, "output_tokens": 0, "total_tokens": 0, "metadata": {"service": "mobile_company_search", "companies_found": 5, "billable_units": 5},
   "original_cost": 0.02, "sellton_cost": 0.03}
]$j$::jsonb);
INSERT INTO public.usage (organization_id, session_id, provider, model_name, api_calls, input_tokens, output_tokens, total_tokens, metadata, original_cost, sellton_cost)
VALUES ('org-x', 'web', 'openai', 'gpt-4.1-mini', 1, 10, 20, 30, '{"service": "email_generation"}', 0.1, 1.000000);

DO $$
DECLARE got jsonb; v4 jsonb; v5 jsonb;
BEGIN
  IF public.usage_display_category('tokens', 'mobile_email_writing') <> 'writing'
     OR public.usage_display_category('tokens', 'mobile_reply_handling') <> 'writing'
     OR public.usage_display_category('tokens', 'mobile_assistant') <> 'research' THEN
    RAISE EXCEPTION '396: the Writing list';
  END IF;
  IF public.usage_provider_label('brain') <> 'Sellton Brain' OR public.usage_provider_label('elevenlabs') <> 'ElevenLabs' THEN
    RAISE EXCEPTION '396: provider labels';
  END IF;
  IF (SELECT count(*) FROM public.action_label_map WHERE provider = '' AND model_name_pattern = '' AND service_name LIKE 'mobile\_%') <> 9 THEN
    RAISE EXCEPTION '396: expected 9 phone service labels';
  END IF;
  IF (SELECT display_label FROM public.action_label_map WHERE service_name = 'mobile_voice') <> 'Sellton voice' THEN
    RAISE EXCEPTION '396: the voice label';
  END IF;

  SELECT jsonb_object_agg(display_category, jsonb_build_object('cost', sellton_cost, 'phones', phones_found, 'companies', companies_found, 'calls', api_calls))
    INTO got FROM public.analytics_usage_rollup_v5('org-x', now() - interval '1 day', now() + interval '1 hour', 'total', NULL, NULL, 'mobile');
  IF got IS DISTINCT FROM '{
      "writing":       {"cost": 0.012300, "phones": 0, "companies": 0, "calls": 12},
      "phone_numbers": {"cost": 0.028890, "phones": 2, "companies": 0, "calls": 2},
      "company_data":  {"cost": 0.030000, "phones": 0, "companies": 5, "calls": 1},
      "research":      {"cost": 0.000000, "phones": 0, "companies": 0, "calls": 3}}'::jsonb THEN
    RAISE EXCEPTION '396: v5 mobile: %', got;
  END IF;

  SELECT jsonb_object_agg(display_category, sellton_cost) INTO got
    FROM public.analytics_usage_rollup_v5('org-x', now() - interval '1 day', now() + interval '1 hour', 'total', NULL, NULL, 'web');
  IF got IS DISTINCT FROM '{"writing": 1.000000}'::jsonb THEN RAISE EXCEPTION '396: v5 web: %', got; END IF;

  SELECT jsonb_agg(to_jsonb(x) ORDER BY x.display_category) INTO v4 FROM public.analytics_usage_rollup_v4('org-x', now() - interval '1 day', now() + interval '1 hour', 'hour') x;
  SELECT jsonb_agg(to_jsonb(x) ORDER BY x.display_category) INTO v5 FROM public.analytics_usage_rollup_v5('org-x', now() - interval '1 day', now() + interval '1 hour', 'hour') x;
  IF v4 IS DISTINCT FROM v5 OR v4 IS NULL THEN RAISE EXCEPTION '396: v5 with NULL must equal v4: % vs %', v4, v5; END IF;

  BEGIN
    PERFORM * FROM public.analytics_usage_rollup_v5('org-x', now() - interval '1 day', now(), 'total', NULL, NULL, 'tablet');
    RAISE EXCEPTION '396: v5 accepted app tablet';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT LIKE 'unsupported usage analytics app%' THEN RAISE; END IF;
  END;

  IF has_function_privilege('anon', 'public.analytics_usage_rollup_v5(text,timestamptz,timestamptz,text,text,text,text)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.analytics_usage_rollup_v5(text,timestamptz,timestamptz,text,text,text,text)', 'EXECUTE') THEN
    RAISE EXCEPTION '396: v5 must be service_role only';
  END IF;
END $$;

-- 397. The summary no longer recounts sessions; the duplicate indexes are gone.
INSERT INTO public.usage_summary (organization_id, provider, model_name, date, total_api_calls, total_tokens, unique_sessions)
VALUES ('org-s', 'openai', 'm', '2026-10-13', 1, 10, 7);
INSERT INTO public.usage (organization_id, session_id, provider, model_name, api_calls, total_tokens, created_at)
VALUES ('org-s', 'another-session', 'openai', 'm', 2, 5, '2026-10-13T12:00:00Z'),
       ('org-s', 'new-day', 'openai', 'm', 1, 1, '2026-10-14T12:00:00Z');
DO $$
BEGIN
  IF position('COUNT(DISTINCT' IN upper(pg_get_functiondef('public.update_usage_summary()'::regprocedure))) > 0 THEN
    RAISE EXCEPTION '397: update_usage_summary still recounts';
  END IF;
  IF (SELECT row(total_api_calls, total_tokens, unique_sessions)::text FROM public.usage_summary WHERE organization_id = 'org-s' AND date = '2026-10-13') <> '(3,15,7)' THEN
    RAISE EXCEPTION '397: an update must add the totals and leave unique_sessions';
  END IF;
  IF (SELECT unique_sessions FROM public.usage_summary WHERE organization_id = 'org-s' AND date = '2026-10-14') <> 0 THEN
    RAISE EXCEPTION '397: a new summary row starts unique_sessions at 0';
  END IF;
  IF (SELECT string_agg(indexname, ',' ORDER BY indexname) FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'usage'
      AND indexname IN ('idx_usage_org_created', 'idx_usage_org_created_desc', 'idx_usage_org_period')) <> 'idx_usage_org_created' THEN
    RAISE EXCEPTION '397: indexes';
  END IF;
END $$;

ROLLBACK;
\echo 'X1 contract (394-397) passed.'
