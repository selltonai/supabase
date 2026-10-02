-- KAN-322 FR-A12 (D10) contract for 388: usage_display_category and analytics_usage_rollup_v4.
-- Disposable database only (tests/run-usage-display-contract.sh). The transaction rolls back every fixture row.
BEGIN;
SET LOCAL TIME ZONE 'UTC';

-- 1. The Writing list is pinned: exactly these twelve services are Writing; any other LLM service is Research.
DO $$
DECLARE
  writing text[] := ARRAY[
    'email_generation_service', 'email_generation', 'hyper_personalized_email_service', 'hyper_personalized_email',
    'linkedin_copywriter_service', 'email_reply_processor_service', 'email_reply_processor', 'reply_handler_service',
    'email_intent_service', 'security_guardrails_service', 'deal_nurture_service', 'call_pitch_service'];
  s text;
  body text;
  listed int;
BEGIN
  FOREACH s IN ARRAY writing LOOP
    IF public.usage_display_category('tokens', s) <> 'writing' THEN RAISE EXCEPTION 'writing list: % is not writing', s; END IF;
    IF public.usage_display_category('b2b_data', s) <> 'company_data' THEN RAISE EXCEPTION 'a non-LLM row of % must stay company_data', s; END IF;
  END LOOP;
  FOREACH s IN ARRAY ARRAY['company_research', 'sales_brief_service', 'retell_service', '', 'EMAIL_GENERATION', 'email_generation '] LOOP
    IF public.usage_display_category('tokens', s) <> 'research' THEN RAISE EXCEPTION 'research fallback: % is not research', s; END IF;
  END LOOP;
  IF public.usage_display_category('tokens', NULL) <> 'research' THEN RAISE EXCEPTION 'a NULL service is research'; END IF;
  IF public.usage_display_category('phones', 'email_generation') <> 'phone_numbers' THEN RAISE EXCEPTION 'phones'; END IF;
  IF public.usage_display_category('b2b_data', NULL) <> 'company_data' THEN RAISE EXCEPTION 'b2b_data'; END IF;
  -- The onboarding interview (provider retell, which 345 files under b2b_data) is Research, by D10.
  IF public.usage_display_category('b2b_data', 'retell') <> 'research' THEN RAISE EXCEPTION 'retell is research'; END IF;

  -- No thirteenth Writing service slips in: count the quoted names in the IN list of the function body.
  SELECT prosrc INTO body FROM pg_proc WHERE oid = 'public.usage_display_category(text, text)'::regprocedure;
  SELECT count(*) INTO listed FROM regexp_matches(split_part(split_part(body, 'IN (', 2), ')', 1), '''[a-z_]+''', 'g');
  IF listed <> 12 THEN RAISE EXCEPTION 'writing list has % entries, expected 12', listed; END IF;
END $$;

-- 2. The result never carries a model, provider or task label.
DO $$
DECLARE result_type text;
BEGIN
  result_type := pg_get_function_result('public.analytics_usage_rollup_v4(text, timestamptz, timestamptz, text, text, text)'::regprocedure);
  IF result_type ~* '(model|provider|task_label|service|original_cost)' THEN RAISE EXCEPTION 'v4 returns an internal field: %', result_type; END IF;
END $$;

-- 3. Only service_role may call it.
DO $$
BEGIN
  IF has_function_privilege('anon', 'public.analytics_usage_rollup_v4(text, timestamptz, timestamptz, text, text, text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.analytics_usage_rollup_v4(text, timestamptz, timestamptz, text, text, text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'v4 must be service_role only';
  END IF;
  IF has_function_privilege('anon', 'public.usage_display_category(text, text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.usage_display_category(text, text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'usage_display_category must be service_role only';
  END IF;
  IF NOT has_function_privilege('service_role', 'public.analytics_usage_rollup_v4(text, timestamptz, timestamptz, text, text, text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'service_role must be able to call v4';
  END IF;
END $$;

-- 4. It refuses to read before the projection backfill is complete (as v3).
DO $$
BEGIN
  UPDATE public.usage_analytics_projection_state SET historical_backfill_completed_at = NULL WHERE singleton;
  BEGIN
    PERFORM * FROM public.analytics_usage_rollup_v4('o', now() - interval '1 day', now());
    RAISE EXCEPTION 'v4 read an incomplete projection';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM <> 'USAGE_ANALYTICS_PROJECTION_NOT_READY' THEN RAISE; END IF;
  END;
END $$;
UPDATE public.usage_analytics_projection_state SET historical_backfill_completed_at = now() WHERE singleton;

-- 5. Fixture: the triggers maintain the projection as rows land.
INSERT INTO public.usage (organization_id, session_id, provider, model_name, api_calls, input_tokens, output_tokens, total_tokens,
                          user_id, campaign_id, created_at, metadata, original_cost, sellton_cost)
VALUES
  -- Writing: 1.000000 + 0.500000 (two models, two LLM providers, one display row).
  ('org-a', 's1', 'openai',    'gpt-4.1-mini', 1, 10, 20, 30, 'user-1', 'camp-1', '2026-07-01T10:15:00Z', '{"service":"email_generation"}', 0.1, 1.000000),
  ('org-a', 's2', 'anthropic', 'claude-x',     1, 40, 60, 100, 'user-2', 'camp-2', '2026-07-02T09:00:00Z', '{"service":"linkedin_copywriter_service"}', 0.05, 0.500000),
  -- Research: 0.250000 + 0.125000 (named service, and no service at all).
  ('org-a', 's3', 'gemini',    'gemini-pro',   2, 100, 0, 100, 'user-1', NULL,    '2026-07-02T11:00:00Z', '{"service":"company_research"}', 0.02, 0.250000),
  ('org-a', 's4', 'xai',       'grok',         1, 5, 5, 10, 'user-2', 'camp-1', '2026-07-03T08:00:00Z', '{}', 0.01, 0.125000),
  -- Company data: 2.000000 with 2 emails found.
  ('org-a', 's5', 'hunter',    'email-finder', 2, 0, 0, 0, 'user-1', 'camp-1', '2026-07-02T11:30:00Z', '{"service":"company_research","emails_found":2,"billable_units":2}', 0.2, 2.000000),
  -- Company data at $0 (infrastructure): hidden.
  ('org-a', 's6', 'unipile',   NULL,           5, 0, 0, 0, 'user-1', 'camp-1', '2026-07-02T12:00:00Z', '{"service":"linkedin_sync"}', 0, 0),
  -- Phone numbers: 3.000000 with 1 phone found.
  ('org-a', 's7', 'airscale',  'airscale-phone-finder', 1, 0, 0, 0, 'user-2', 'camp-2', '2026-07-02T12:45:00Z', '{"action":"phone_finder","phones_found":1}', 0.3, 3.000000),
  -- Writing at $0 (pricing missed): stays, with its 50 tokens.
  ('org-a', 's11', 'openai',   'gpt-4.1-mini', 1, 20, 30, 50, 'user-1', 'camp-1', '2026-07-03T09:00:00Z', '{"service":"email_generation"}', 0, 0),
  -- Company data that cost Sellton nothing but has an original cost: stays.
  ('org-a', 's12', 'hunter',   'email-finder', 1, 0, 0, 0, 'user-1', 'camp-1', '2026-07-03T09:30:00Z', '{"service":"cost_split"}', 0.05, 0),
  -- Company data with tokens and no cost (an unlisted LLM provider): stays, so tokens still equal v3's.
  ('org-a', 's13', 'google',   'gemma',        1, 400, 100, 500, 'user-2', 'camp-2', '2026-07-03T10:00:00Z', '{"service":"misc"}', 0, 0),
  -- The onboarding interview: Research, 0.700000.
  ('org-a', 's14', 'retell',   NULL,           1, 0, 0, 0, 'user-2', 'camp-2', '2026-07-03T11:00:00Z', '{"service":"retell"}', 0.7, 0.700000),
  -- Research at $0 with no tokens (a cached call): not infrastructure, so it stays and its call counts.
  ('org-a', 's16', 'openai',   'gpt-4.1-mini', 1, 0, 0, 0, 'user-1', NULL, '2026-07-03T12:30:00Z', '{"service":"company_research"}', 0, 0),
  -- Company data Sellton charges for with no provider cost: stays, 0.300000.
  ('org-a', 's17', 'b2b_enrichment', 'b2b-people_search', 1, 0, 0, 0, 'user-1', 'camp-1', '2026-07-03T13:00:00Z', '{"service":"flat"}', 0, 0.300000),
  -- Exactly at the window's end (v3 includes p_end): Writing, 0.010000.
  ('org-a', 's15', 'openai',   'gpt-4.1-mini', 1, 2, 3, 5, 'user-1', 'camp-1', '2026-07-04T00:00:00Z', '{"service":"email_generation"}', 0.001, 0.010000),
  -- Another organization: never counted.
  ('org-b', 's8', 'openai',    'gpt-4.1-mini', 1, 999, 1, 1000, 'user-9', 'camp-9', '2026-07-01T10:15:00Z', '{"service":"email_generation"}', 9.9, 99.000000);

DO $$
DECLARE
  got jsonb;
  v3_total numeric;
  v4_total numeric;
  r record;
BEGIN
  -- 5a. Whole days plus the row at p_end: four categories, the $0 infrastructure row hidden with its 5 calls.
  SELECT jsonb_object_agg(display_category, jsonb_build_object('cost', sellton_cost, 'tokens', total_tokens, 'emails', emails_found, 'phones', phones_found, 'calls', api_calls))
    INTO got
    FROM public.analytics_usage_rollup_v4('org-a', '2026-07-01T00:00:00Z', '2026-07-04T00:00:00Z');
  IF got IS DISTINCT FROM '{
      "writing":       {"cost": 1.510000, "tokens": 185, "emails": 0, "phones": 0, "calls": 4},
      "research":      {"cost": 1.075000, "tokens": 110, "emails": 0, "phones": 0, "calls": 5},
      "company_data":  {"cost": 2.300000, "tokens": 500, "emails": 2, "phones": 0, "calls": 5},
      "phone_numbers": {"cost": 3.000000, "tokens": 0,   "emails": 0, "phones": 1, "calls": 1}
    }'::jsonb THEN
    RAISE EXCEPTION 'whole-day totals: %', got;
  END IF;

  -- 5b. Cost and tokens equal v3's for the same window (a hidden group has neither). Borce's acceptance check.
  SELECT ROUND(SUM(sellton_cost), 6) INTO v3_total FROM public.analytics_usage_rollup_v3('org-a', '2026-07-01T00:00:00Z', '2026-07-04T00:00:00Z', 'total');
  SELECT ROUND(SUM(sellton_cost), 6) INTO v4_total FROM public.analytics_usage_rollup_v4('org-a', '2026-07-01T00:00:00Z', '2026-07-04T00:00:00Z');
  IF v3_total IS DISTINCT FROM v4_total OR v4_total IS DISTINCT FROM 7.885000 THEN RAISE EXCEPTION 'v3 % vs v4 %', v3_total, v4_total; END IF;
  SELECT SUM(total_tokens) INTO v3_total FROM public.analytics_usage_rollup_v3('org-a', '2026-07-01T00:00:00Z', '2026-07-04T00:00:00Z', 'total');
  SELECT SUM(total_tokens) INTO v4_total FROM public.analytics_usage_rollup_v4('org-a', '2026-07-01T00:00:00Z', '2026-07-04T00:00:00Z');
  IF v3_total IS DISTINCT FROM v4_total OR v4_total <> 795 THEN RAISE EXCEPTION 'tokens: v3 % vs v4 %', v3_total, v4_total; END IF;

  -- 5b2. A window mixing whole days with partial edges at both ends matches v3 in cost and tokens.
  FOR r IN SELECT * FROM (VALUES
      ('2026-07-01T10:00:00Z'::timestamptz, '2026-07-03T12:00:00Z'::timestamptz),
      ('2026-07-01T10:30:00Z'::timestamptz, '2026-07-03T09:30:00Z'::timestamptz),
      ('2026-07-03T00:00:00Z'::timestamptz, '2026-07-04T00:00:00Z'::timestamptz),
      -- Starts exactly on a row (s2 at 09:00): v3 counts it, so must v4.
      ('2026-07-02T09:00:00Z'::timestamptz, '2026-07-03T12:00:00Z'::timestamptz)) w(s, e) LOOP
    IF (SELECT (ROUND(SUM(sellton_cost), 6), SUM(total_tokens)) FROM public.analytics_usage_rollup_v4('org-a', r.s, r.e))
       IS DISTINCT FROM
       (SELECT (ROUND(SUM(sellton_cost), 6), SUM(total_tokens)) FROM public.analytics_usage_rollup_v3('org-a', r.s, r.e, 'total')) THEN
      RAISE EXCEPTION 'mixed window % - % differs from v3', r.s, r.e;
    END IF;
  END LOOP;
  -- The row at exactly p_end counts (as in v3).
  SELECT ROUND(SUM(sellton_cost), 6) INTO v4_total FROM public.analytics_usage_rollup_v4('org-a', '2026-07-03T12:00:00Z', '2026-07-04T00:00:00Z');
  -- s16 ($0) + s17 (0.30) + s15 at exactly p_end (0.01).
  IF v4_total IS DISTINCT FROM 0.310000 THEN RAISE EXCEPTION 'row at p_end: %', v4_total; END IF;

  -- 5c. Partial-day edges (contribution rows) count each usage row once: 10:00 on day 1 to 12:00 on day 2.
  SELECT ROUND(SUM(sellton_cost), 6) INTO v4_total FROM public.analytics_usage_rollup_v4('org-a', '2026-07-01T10:00:00Z', '2026-07-02T12:00:00Z');
  SELECT ROUND(SUM(sellton_cost), 6) INTO v3_total FROM public.analytics_usage_rollup_v3('org-a', '2026-07-01T10:00:00Z', '2026-07-02T12:00:00Z', 'total');
  -- 1.0 (07-01 10:15) + 0.5 + 0.25 + 2.0 (07-02 09:00..11:30); the 12:45 phone row is outside.
  IF v4_total <> 3.750000 OR v3_total IS DISTINCT FROM v4_total THEN RAISE EXCEPTION 'edge window: v4 % v3 %', v4_total, v3_total; END IF;

  -- 5d. Day and hour buckets add up to the same total, and each bucket has at most one row per category.
  SELECT ROUND(SUM(sellton_cost), 6) INTO v4_total FROM public.analytics_usage_rollup_v4('org-a', '2026-07-01T00:00:00Z', '2026-07-04T00:00:00Z', 'day');
  IF v4_total IS DISTINCT FROM 7.885000 THEN RAISE EXCEPTION 'day buckets: %', v4_total; END IF;
  SELECT ROUND(SUM(sellton_cost), 6) INTO v4_total FROM public.analytics_usage_rollup_v4('org-a', '2026-07-01T00:00:00Z', '2026-07-04T00:00:00Z', 'hour');
  IF v4_total IS DISTINCT FROM 7.885000 THEN RAISE EXCEPTION 'hour buckets: %', v4_total; END IF;
  FOR r IN SELECT bucket_start, display_category, count(*) AS n
             FROM public.analytics_usage_rollup_v4('org-a', '2026-07-01T00:00:00Z', '2026-07-04T00:00:00Z', 'day')
            GROUP BY 1, 2 HAVING count(*) > 1 LOOP
    RAISE EXCEPTION 'duplicate bucket row % %', r.bucket_start, r.display_category;
  END LOOP;

  -- 5e. "Just me" and one play.
  SELECT jsonb_object_agg(display_category, sellton_cost) INTO got
    FROM public.analytics_usage_rollup_v4('org-a', '2026-07-01T00:00:00Z', '2026-07-04T00:00:00Z', 'total', NULL, 'user-2');
  IF got IS DISTINCT FROM '{"writing": 0.500000, "research": 0.825000, "company_data": 0, "phone_numbers": 3.000000}'::jsonb THEN RAISE EXCEPTION 'user filter: %', got; END IF;
  SELECT jsonb_object_agg(display_category, sellton_cost) INTO got
    FROM public.analytics_usage_rollup_v4('org-a', '2026-07-01T00:00:00Z', '2026-07-04T00:00:00Z', 'total', 'camp-1', NULL);
  IF got IS DISTINCT FROM '{"writing": 1.010000, "research": 0.125000, "company_data": 2.300000}'::jsonb THEN RAISE EXCEPTION 'campaign filter: %', got; END IF;
  SELECT jsonb_object_agg(display_category, sellton_cost) INTO got
    FROM public.analytics_usage_rollup_v4('org-a', '2026-07-01T00:00:00Z', '2026-07-04T00:00:00Z', 'total', 'all', '');
  IF (got ->> 'writing')::numeric IS DISTINCT FROM 1.51 THEN RAISE EXCEPTION '"all" and empty filters mean everything: %', got; END IF;

  -- 5f. Another organization sees only its own row; an unknown one sees nothing.
  SELECT jsonb_object_agg(display_category, sellton_cost) INTO got
    FROM public.analytics_usage_rollup_v4('org-b', '2026-07-01T00:00:00Z', '2026-07-04T00:00:00Z');
  IF got IS DISTINCT FROM '{"writing": 99.000000}'::jsonb THEN RAISE EXCEPTION 'org-b: %', got; END IF;
  IF EXISTS (SELECT 1 FROM public.analytics_usage_rollup_v4('org-none', '2026-07-01T00:00:00Z', '2026-07-04T00:00:00Z')) THEN
    RAISE EXCEPTION 'unknown org returned rows';
  END IF;

  -- 5g. A bad or missing bucket is refused.
  BEGIN
    PERFORM * FROM public.analytics_usage_rollup_v4('org-a', '2026-07-01T00:00:00Z', '2026-07-04T00:00:00Z', NULL);
    RAISE EXCEPTION 'NULL bucket accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT LIKE 'unsupported usage analytics bucket%' THEN RAISE; END IF;
  END;
  BEGIN
    PERFORM * FROM public.analytics_usage_rollup_v4('org-a', '2026-07-01T00:00:00Z', '2026-07-04T00:00:00Z', 'week');
    RAISE EXCEPTION 'week bucket accepted';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT LIKE 'unsupported usage analytics bucket%' THEN RAISE; END IF;
  END;
END $$;

-- 6. The projection merges rows with the same labels in one bucket. Here a $0 row (3 calls) and a paid one (1 call)
--    share a projection key, so the group is paid and stays whole: cost and counts exact, calls 4. Edges are grouped
--    by the same key. Cost and tokens never depend on the window; the calls of a $0 group may (an edge holds only the
--    key's in-window rows). Only $0 groups without tokens drop out.
INSERT INTO public.usage (organization_id, session_id, provider, api_calls, user_id, created_at, metadata, original_cost, sellton_cost)
VALUES ('org-c', 's9', 'unipile', 3, 'u', '2026-07-02T10:00:00Z', '{}', 0, 0),
       ('org-c', 's10', 'aiark', 1, 'u', '2026-07-02T10:30:00Z', '{"people_found":4}', 0.1, 0.400000);
DO $$
DECLARE got jsonb;
BEGIN
  SELECT jsonb_object_agg(display_category, jsonb_build_object('cost', sellton_cost, 'people', people_found, 'calls', api_calls)) INTO got
    FROM public.analytics_usage_rollup_v4('org-c', '2026-07-01T00:00:00Z', '2026-07-04T00:00:00Z');
  IF got IS DISTINCT FROM '{"company_data": {"cost": 0.400000, "people": 4, "calls": 4}}'::jsonb THEN RAISE EXCEPTION 'mixed company data: %', got; END IF;
  -- The same rows seen through a partial edge (window from 09:00) are grouped the same way: calls stay 4.
  SELECT jsonb_object_agg(display_category, jsonb_build_object('cost', sellton_cost, 'people', people_found, 'calls', api_calls)) INTO got
    FROM public.analytics_usage_rollup_v4('org-c', '2026-07-02T09:00:00Z', '2026-07-04T00:00:00Z');
  IF got IS DISTINCT FROM '{"company_data": {"cost": 0.400000, "people": 4, "calls": 4}}'::jsonb THEN RAISE EXCEPTION 'edge grouping: %', got; END IF;
END $$;

-- 7. Rows that differ only in run, or only in task, are different projection keys. A $0 row of each is hidden on a
--    whole day; the mid-day edge must group by the same key and hide it too, so both windows show the paid call only.
INSERT INTO public.usage (organization_id, session_id, provider, model_name, api_calls, user_id, run_id, created_at, metadata, original_cost, sellton_cost)
VALUES ('org-d', 's20', 'ai_ark', 'aiark-people', 3, 'u', 'run-a', '2026-07-02T10:00:00Z', '{"action":"people_search"}', 0, 0),
       ('org-d', 's21', 'ai_ark', 'aiark-people', 1, 'u', 'run-b', '2026-07-02T10:30:00Z', '{"action":"people_search"}', 0.1, 0.400000),
       ('org-d', 's22', 'ai_ark', 'aiark-people', 2, 'u', 'run-b', '2026-07-02T10:40:00Z', '{"action":"person_profile"}', 0, 0);
DO $$
DECLARE whole jsonb; edge jsonb; labels int;
BEGIN
  -- The fixture is only meaningful if s21 and s22 really carry different task labels.
  SELECT count(DISTINCT task_label) INTO labels FROM public.usage_analytics_projection_contributions WHERE organization_id = 'org-d' AND run_id = 'run-b';
  IF labels <> 2 THEN RAISE EXCEPTION 'fixture: expected two task labels, got %', labels; END IF;
  SELECT jsonb_object_agg(display_category, api_calls) INTO whole FROM public.analytics_usage_rollup_v4('org-d', '2026-07-01T00:00:00Z', '2026-07-04T00:00:00Z');
  SELECT jsonb_object_agg(display_category, api_calls) INTO edge FROM public.analytics_usage_rollup_v4('org-d', '2026-07-02T09:00:00Z', '2026-07-04T00:00:00Z');
  IF whole IS DISTINCT FROM '{"company_data": 1}'::jsonb OR edge IS DISTINCT FROM whole THEN
    RAISE EXCEPTION 'run and task keys: whole % edge %', whole, edge;
  END IF;
END $$;

ROLLBACK;
