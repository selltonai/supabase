-- Usage Analytics projection contract test.
--
-- Run only against a disposable database after applying the usage analytics
-- migrations through 345_usage-analytics-projection.sql:
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f tests/usage-analytics-projection.contract.sql
--
-- The transaction rolls back all fixture rows. Do not run this against a
-- production database because the test intentionally disables user triggers
-- while creating its historical-backfill fixture.

BEGIN;

SET LOCAL TIME ZONE 'UTC';

ALTER TABLE public.usage DISABLE TRIGGER USER;

INSERT INTO public.usage (
  id, organization_id, session_id, provider, model_name, api_calls,
  input_tokens, output_tokens, total_tokens, user_id, campaign_id, run_id,
  created_at, metadata, original_cost, sellton_cost
)
VALUES
  (
    '11111111-1111-4111-8111-111111111111',
    'usage-analytics-contract-org-a',
    'usage-analytics-contract-session-a',
    'openai', 'gpt-4.1-mini', 1, 10, 20, 30, 'usage-analytics-contract-user-a',
    'usage-analytics-contract-campaign-a', 'usage-analytics-contract-run-a',
    '2026-07-01T10:15:00Z',
    '{"service":"email_generation","operation":"draft"}'::jsonb,
    0.100000, 1.000000
  ),
  (
    '22222222-2222-4222-8222-222222222222',
    'usage-analytics-contract-org-a',
    'usage-analytics-contract-session-b',
    'hunter', 'email-finder', 2, 0, 0, 0, 'usage-analytics-contract-user-b',
    NULL, 'usage-analytics-contract-run-b',
    '2026-07-02T11:30:00Z',
    '{"service":"company_research","operation":"email_finder","emails_found":2,"billable_units":2}'::jsonb,
    0.200000, 2.000000
  ),
  (
    '33333333-3333-4333-8333-333333333333',
    'usage-analytics-contract-org-a',
    'usage-analytics-contract-session-c',
    'airscale', 'airscale-phone-finder', 1, 0, 0, 0, NULL,
    'usage-analytics-contract-campaign-a', 'usage-analytics-contract-run-c',
    '2026-07-02T12:45:00Z',
    '{"service":"company_research","operation":"phone_finder","action":"phone_finder","phones_found":1,"success":true}'::jsonb,
    0.300000, 3.000000
  ),
  (
    '44444444-4444-4444-8444-444444444444',
    'usage-analytics-contract-org-b',
    'usage-analytics-contract-session-d',
    'openai', 'gpt-4.1-mini', 1, 999, 1, 1000, 'usage-analytics-contract-user-c',
    'usage-analytics-contract-campaign-b', 'usage-analytics-contract-run-d',
    '2026-07-01T10:15:00Z',
    '{"service":"email_generation","operation":"draft"}'::jsonb,
    9.900000, 99.000000
  ),
  (
    '55555555-5555-4555-8555-555555555555',
    'usage-analytics-contract-org-a',
    'usage-analytics-contract-session-e',
    'openai', 'gpt-correction', 1, 5, 5, 10, NULL,
    NULL, 'usage-analytics-contract-run-e',
    '2026-07-03T09:00:00Z',
    '{"service":"company_research","operation":"draft"}'::jsonb,
    0.010000, 0.500000
  );

ALTER TABLE public.usage ENABLE TRIGGER USER;

DO $$
DECLARE
  first_backfill_count bigint;
  second_backfill_count bigint;
  projected_cost numeric;
  raw_cost numeric;
BEGIN
  SELECT inserted_count
  INTO first_backfill_count
  FROM public.backfill_usage_analytics_projection(
    p_start => '2026-07-01T00:00:00Z',
    p_end => '2026-07-04T00:00:00Z',
    p_batch_size => 100
  );

  IF first_backfill_count <> 5 THEN
    RAISE EXCEPTION 'expected five historical source contributions, got %', first_backfill_count;
  END IF;

  SELECT COALESCE(MAX(inserted_count), 0)
  INTO second_backfill_count
  FROM public.backfill_usage_analytics_projection(
    p_start => '2026-07-01T00:00:00Z',
    p_end => '2026-07-04T00:00:00Z',
    p_batch_size => 100
  );

  IF second_backfill_count <> 0 THEN
    RAISE EXCEPTION 'historical backfill must be idempotent, got % duplicate rows', second_backfill_count;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.usage_analytics_projection_rollups
    WHERE organization_id = 'usage-analytics-contract-org-a'
      AND bucket_granularity = 'day'
      AND bucket_start = '2026-07-02T00:00:00Z'
      AND category = 'b2b_data'
      AND emails_found = 2
      AND sellton_cost = 2.000000
  ) THEN
    RAISE EXCEPTION 'B2B usage was not projected to its UTC daily bucket';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.usage_analytics_projection_rollups
    WHERE organization_id = 'usage-analytics-contract-org-a'
      AND bucket_granularity = 'hour'
      AND bucket_start = '2026-07-02T12:00:00Z'
      AND category = 'phones'
      AND phones_found = 1
      AND units = 1
  ) THEN
    RAISE EXCEPTION 'phone usage was not projected to its UTC hourly bucket';
  END IF;

  SELECT COALESCE(SUM(sellton_cost), 0)
  INTO projected_cost
  FROM public.usage_analytics_projection_rollups
  WHERE organization_id = 'usage-analytics-contract-org-a'
    AND bucket_granularity = 'day';

  IF projected_cost <> 6.500000 THEN
    RAISE EXCEPTION 'organization projection leaked or lost cost: expected 6.5, got %', projected_cost;
  END IF;

  SELECT COALESCE(SUM(sellton_cost), 0)
  INTO projected_cost
  FROM public.usage_analytics_projection_rollups
  WHERE organization_id = 'usage-analytics-contract-org-b'
    AND bucket_granularity = 'day';

  IF projected_cost <> 99.000000 THEN
    RAISE EXCEPTION 'organization isolation failed: expected 99, got %', projected_cost;
  END IF;
END;
$$;

UPDATE public.usage
SET provider = 'airscale',
    model_name = 'airscale-phone-correction',
    metadata = '{"service":"company_research","operation":"phone_finder","action":"phone_finder","phones_found":2,"success":true}'::jsonb,
    sellton_cost = 4.000000
WHERE id = '55555555-5555-4555-8555-555555555555';

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.usage_analytics_projection_contributions
    WHERE usage_id = '55555555-5555-4555-8555-555555555555'
      AND category <> 'phones'
  ) THEN
    RAISE EXCEPTION 'correction did not replace the old contribution category';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.usage_analytics_projection_rollups
    WHERE organization_id = 'usage-analytics-contract-org-a'
      AND raw_model_name = 'gpt-correction'
      AND usage_row_count <> 0
  ) THEN
    RAISE EXCEPTION 'correction left an old rollup contribution behind';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.usage_analytics_projection_rollups
    WHERE organization_id = 'usage-analytics-contract-org-a'
      AND raw_model_name = 'airscale-phone-correction'
      AND category = 'phones'
      AND phones_found = 2
      AND sellton_cost = 4.000000
  ) THEN
    RAISE EXCEPTION 'correction did not add the new contribution exactly once';
  END IF;
END;
$$;

DELETE FROM public.usage
WHERE id = '55555555-5555-4555-8555-555555555555';

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.usage_analytics_projection_contributions
    WHERE usage_id = '55555555-5555-4555-8555-555555555555'
  ) THEN
    RAISE EXCEPTION 'delete did not remove the source contribution';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.usage_analytics_projection_rollups
    WHERE organization_id = 'usage-analytics-contract-org-a'
      AND raw_model_name = 'airscale-phone-correction'
  ) THEN
    RAISE EXCEPTION 'delete did not remove the aggregate contribution';
  END IF;
END;
$$;

SELECT public.complete_usage_analytics_projection_backfill();

DO $$
BEGIN
  IF EXISTS (
    (
      SELECT bucket_start, category, campaign_id, user_id, task_label, model_label,
        api_calls, input_tokens, output_tokens, total_tokens, grounding_queries,
        units, emails_found, people_found, companies_found, phones_found,
        original_cost, sellton_cost
      FROM public.analytics_usage_rollup_v2(
        'usage-analytics-contract-org-a',
        '2026-07-01T00:00:00Z',
        '2026-07-04T00:00:00Z',
        'day'
      )
      EXCEPT ALL
      SELECT bucket_start, category, campaign_id, user_id, task_label, model_label,
        api_calls, input_tokens, output_tokens, total_tokens, grounding_queries,
        units, emails_found, people_found, companies_found, phones_found,
        original_cost, sellton_cost
      FROM public.analytics_usage_rollup_v3(
        'usage-analytics-contract-org-a',
        '2026-07-01T00:00:00Z',
        '2026-07-04T00:00:00Z',
        'day'
      )
    )
    UNION ALL
    (
      SELECT bucket_start, category, campaign_id, user_id, task_label, model_label,
        api_calls, input_tokens, output_tokens, total_tokens, grounding_queries,
        units, emails_found, people_found, companies_found, phones_found,
        original_cost, sellton_cost
      FROM public.analytics_usage_rollup_v3(
        'usage-analytics-contract-org-a',
        '2026-07-01T00:00:00Z',
        '2026-07-04T00:00:00Z',
        'day'
      )
      EXCEPT ALL
      SELECT bucket_start, category, campaign_id, user_id, task_label, model_label,
        api_calls, input_tokens, output_tokens, total_tokens, grounding_queries,
        units, emails_found, people_found, companies_found, phones_found,
        original_cost, sellton_cost
      FROM public.analytics_usage_rollup_v2(
        'usage-analytics-contract-org-a',
        '2026-07-01T00:00:00Z',
        '2026-07-04T00:00:00Z',
        'day'
      )
    )
  ) THEN
    RAISE EXCEPTION 'analytics_usage_rollup_v3 does not match analytics_usage_rollup_v2';
  END IF;
END;
$$;

DO $$
BEGIN
  IF EXISTS (
    (
      SELECT bucket_start, category, campaign_id, user_id, task_label, model_label,
        api_calls, input_tokens, output_tokens, total_tokens, grounding_queries,
        units, emails_found, people_found, companies_found, phones_found,
        original_cost, sellton_cost
      FROM public.analytics_usage_rollup_v2(
        'usage-analytics-contract-org-a',
        '2026-07-02T11:45:00Z',
        '2026-07-02T12:50:00Z',
        'hour'
      )
      EXCEPT ALL
      SELECT bucket_start, category, campaign_id, user_id, task_label, model_label,
        api_calls, input_tokens, output_tokens, total_tokens, grounding_queries,
        units, emails_found, people_found, companies_found, phones_found,
        original_cost, sellton_cost
      FROM public.analytics_usage_rollup_v3(
        'usage-analytics-contract-org-a',
        '2026-07-02T11:45:00Z',
        '2026-07-02T12:50:00Z',
        'hour'
      )
    )
    UNION ALL
    (
      SELECT bucket_start, category, campaign_id, user_id, task_label, model_label,
        api_calls, input_tokens, output_tokens, total_tokens, grounding_queries,
        units, emails_found, people_found, companies_found, phones_found,
        original_cost, sellton_cost
      FROM public.analytics_usage_rollup_v3(
        'usage-analytics-contract-org-a',
        '2026-07-02T11:45:00Z',
        '2026-07-02T12:50:00Z',
        'hour'
      )
      EXCEPT ALL
      SELECT bucket_start, category, campaign_id, user_id, task_label, model_label,
        api_calls, input_tokens, output_tokens, total_tokens, grounding_queries,
        units, emails_found, people_found, companies_found, phones_found,
        original_cost, sellton_cost
      FROM public.analytics_usage_rollup_v2(
        'usage-analytics-contract-org-a',
        '2026-07-02T11:45:00Z',
        '2026-07-02T12:50:00Z',
        'hour'
      )
    )
  ) THEN
    RAISE EXCEPTION 'analytics_usage_rollup_v3 does not preserve a partial-hour v2 range';
  END IF;
END;
$$;

ROLLBACK;
