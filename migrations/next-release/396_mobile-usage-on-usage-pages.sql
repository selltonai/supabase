-- ============================================================
-- Migration: mobile-usage-on-usage-pages (stage: next-release/396; renumber at promotion)
-- Date:      2026-10-14
-- Purpose:   KAN-333 task 3 (X1). The phone's usage rows (written by 395's record_usage_batch_v1, metadata.service
--            mobile_*) land on the Usage pages. Must be on stage before the first phone row: the 345 projection files a
--            row when it is inserted, and there is no backfill.
--              1. usage_analytics_projection_contribution (345): brain + metadata.action 'phone_finder' -> phones;
--                 elevenlabs joins the token providers (shows under Research via usage_display_category).
--                 Every other brain row stays b2b_data (Company data), counted from companies_found, people_found,
--                 emails_found, phones_found, billable_units as today.
--              2. usage_display_category (388): mobile_email_writing and mobile_reply_handling join the Writing list.
--              3. usage_provider_label (326): brain -> Sellton Brain, elevenlabs -> ElevenLabs.
--              4. action_label_map (249): the nine phone services, any provider and model, priority 1.
--              5. analytics_usage_rollup_v5: v4 plus p_app ('mobile', 'web' or NULL for both). v4 is unchanged.
--            Bodies 1 to 3 start from the live stage definitions (pg_get_functiondef, 2026-10-14), not from older files.
-- Projects:  selltonai-database/supabase (owner); readers: the mobile service reads v5 (p_app 'mobile', service role);
--            the web keeps reading v3 and v4, unchanged. No stage usage row has provider brain or elevenlabs or a
--            mobile_* service today, so no existing projection row changes category.
-- Contract:  Function bodies and new rows in action_label_map only. No table, column or trigger change.
-- Rollback:  migrations/next-release/rollback/396_mobile-usage-on-usage-pages.rollback.sql
-- ============================================================

CREATE OR REPLACE FUNCTION public.usage_analytics_projection_contribution(p_usage usage)
 RETURNS SETOF usage_analytics_projection_contributions
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  WITH base_usage AS (
    SELECT
      p_usage.organization_id,
      p_usage.created_at AS occurred_at,
      p_usage.provider,
      p_usage.model_name,
      p_usage.campaign_id,
      p_usage.user_id,
      p_usage.run_id,
      COALESCE(p_usage.api_calls, 0)::numeric AS api_calls,
      COALESCE(p_usage.input_tokens, 0)::numeric AS input_tokens,
      COALESCE(p_usage.output_tokens, 0)::numeric AS output_tokens,
      (
        CASE
          WHEN COALESCE(p_usage.total_tokens, 0) > 0 THEN COALESCE(p_usage.total_tokens, 0)
          ELSE COALESCE(p_usage.input_tokens, 0) + COALESCE(p_usage.output_tokens, 0)
        END
      )::numeric AS total_tokens,
      COALESCE(p_usage.original_cost, 0)::numeric AS original_cost,
      COALESCE(p_usage.sellton_cost, 0)::numeric AS sellton_cost,
      public.usage_metadata_object(p_usage.metadata) AS metadata
    WHERE p_usage.created_at IS NOT NULL
  ),
  categorized AS (
    SELECT
      b.*,
      lower(trim(COALESCE(b.metadata ->> 'action', ''))) AS action_key,
      COALESCE(NULLIF(b.metadata ->> 'provider_name', ''), b.provider, '') AS provider_name,
      COALESCE(
        NULLIF(b.metadata ->> 'effective_provider', ''),
        NULLIF(b.metadata ->> 'provider', ''),
        NULLIF(b.metadata ->> 'provider_name', ''),
        b.provider,
        ''
      ) AS effective_provider,
      COALESCE(b.metadata ->> 'research_flow', '') AS research_flow,
      COALESCE(b.metadata ->> 'service', '') AS service_name,
      COALESCE(b.metadata ->> 'operation', '') AS operation_name,
      CASE
        WHEN b.provider = 'airscale'
          AND (
            COALESCE(b.metadata ->> 'action', '') = 'phone_finder'
            OR COALESCE(b.model_name, '') LIKE 'airscale-phone%'
          ) THEN 'phones'
        -- 396 (KAN-333 X1): Sellton Brain's phone finding is phones, as Airscale's is; every other brain row stays b2b_data.
        WHEN b.provider = 'brain' AND COALESCE(b.metadata ->> 'action', '') = 'phone_finder' THEN 'phones'
        -- 396: the phone's voice (ElevenLabs characters) counts with the token providers, so it shows under Research.
        WHEN b.provider IN ('openai', 'anthropic', 'deepseek', 'togetherai', 'perplexity', 'gemini', 'mistral', 'xai', 'grok', 'elevenlabs') THEN 'tokens'
        ELSE 'b2b_data'
      END AS derived_category
    FROM base_usage b
  ),
  labeled AS (
    SELECT
      c.*,
      CASE
        WHEN c.service_name = 'company_research' THEN
          CASE
            WHEN c.effective_provider = 'both' AND c.provider_name = 'gemini' THEN 'Company research · Gemini Summarizer'
            WHEN c.effective_provider = 'both' AND c.provider_name <> '' THEN 'Company research · ' || public.usage_provider_label(c.provider_name)
            WHEN c.effective_provider = 'both' THEN 'Company research · Multi-provider'
            WHEN c.effective_provider = 'gemini_ultra_lean' OR c.research_flow = 'ultra_lean' THEN 'Company research · Gemini Ultra Lean'
            WHEN c.effective_provider IN ('grok', 'xai') OR c.research_flow = 'advanced_research' THEN 'Company research · Advanced Research'
            WHEN c.effective_provider = 'gemini_pro' OR c.research_flow = 'gemini_pro' THEN 'Company research · Gemini Pro Legacy'
            WHEN (c.effective_provider = 'gemini' OR c.provider_name = 'gemini') AND c.research_flow = 'compact' THEN 'Company research · Gemini Compact'
            WHEN c.effective_provider <> '' THEN 'Company research · ' || public.usage_provider_label(c.effective_provider)
            WHEN c.provider_name <> '' THEN 'Company research · ' || public.usage_provider_label(c.provider_name)
            ELSE 'Company research · Unknown'
          END
        WHEN c.provider = 'gemini' AND public.usage_metadata_number(c.metadata, 'grounding_queries') > 0 THEN 'Web search (grounding)'
        WHEN c.derived_category = 'phones' THEN 'Phone discovery'
        WHEN c.provider IN ('hunter', 'icypeas', 'apollo') THEN 'Email finder'
        WHEN c.provider = 'exa' THEN 'Web research'
        WHEN c.provider = 'ai_ark' AND (c.action_key = 'similar_companies' OR COALESCE(c.model_name, '') LIKE '%similar_companies%') THEN 'Company search'
        WHEN c.provider = 'ai_ark' AND (c.action_key = 'person_profile' OR COALESCE(c.model_name, '') LIKE '%person_profile%') THEN 'Contact enrichment'
        WHEN c.provider = 'ai_ark' THEN 'People search'
        WHEN c.provider = 'b2b_enrichment' AND COALESCE(c.model_name, '') LIKE 'b2b-email_verifier%' THEN 'Email verifier'
        WHEN c.provider = 'b2b_enrichment' AND COALESCE(c.model_name, '') LIKE 'b2b-email_finder%' THEN 'Email finder'
        WHEN c.provider = 'b2b_enrichment' AND COALESCE(c.model_name, '') LIKE 'b2b-people_search%' THEN 'People search'
        WHEN c.provider = 'b2b_enrichment' AND COALESCE(c.model_name, '') LIKE 'b2b-similar_companies%' THEN 'Company search'
        WHEN c.provider = 'b2b_enrichment' AND COALESCE(c.model_name, '') LIKE 'b2b-company_profile%' THEN 'Company search'
        WHEN c.provider = 'b2b_enrichment' THEN 'Contact enrichment'
        ELSE 'LLM generation'
      END AS derived_task_label,
      CASE
        WHEN c.derived_category = 'tokens' THEN c.model_name
        ELSE NULL
      END AS derived_model_label
    FROM categorized c
  ),
  metric_inputs AS (
    SELECT
      l.*,
      public.usage_metadata_count(
        l.metadata,
        VARIADIC ARRAY[
          'found_emails', 'emails_found', 'email_matches', 'returned_email_matches',
          'returned_emails', 'emails_returned', 'emails', 'email_found', 'found_email', 'email'
        ]
      ) AS found_emails_raw,
      public.usage_metadata_count(
        l.metadata,
        VARIADIC ARRAY[
          'profiles_returned', 'people_found', 'people_returned', 'returned_people',
          'returned_profiles', 'profile_count', 'profiles_found', 'results_found'
        ]
      ) AS people_returned_raw,
      public.usage_metadata_count(
        l.metadata,
        VARIADIC ARRAY[
          'companies_found', 'companies_returned', 'returned_companies', 'company_count',
          'company_profiles_returned', 'similar_companies'
        ]
      ) AS companies_returned_raw,
      public.usage_metadata_count(l.metadata, VARIADIC ARRAY['results', 'items', 'data']) AS generic_results,
      public.usage_metadata_count(
        l.metadata,
        VARIADIC ARRAY[
          'phones_found', 'phone_found', 'phone_number', 'phone_numbers', 'phone',
          'phones', 'mobile_phone', 'mobile'
        ]
      ) AS phones_found_raw,
      public.usage_metadata_number(l.metadata, 'billable_units') AS billable_units,
      public.usage_metadata_number(l.metadata, 'grounding_queries') AS metadata_grounding_queries,
      public.usage_metadata_boolean(l.metadata, 'success') AS is_success,
      (
        l.action_key = 'people_search'
        OR COALESCE(l.model_name, '') LIKE '%people_search%'
        OR (l.provider = 'ai_ark' AND l.action_key = '')
      ) AS is_people_search,
      (
        l.action_key IN ('similar_companies', 'company_search', 'company_profile')
        OR COALESCE(l.model_name, '') LIKE '%similar_companies%'
        OR COALESCE(l.model_name, '') LIKE '%company_profile%'
      ) AS is_company_search,
      (
        l.provider IN ('hunter', 'icypeas')
        OR (l.provider = 'apollo' AND (l.action_key = 'email_finder' OR COALESCE(l.model_name, '') LIKE '%email_finder%'))
        OR (l.provider = 'airscale' AND (l.action_key = 'email_finder' OR COALESCE(l.model_name, '') LIKE '%email_finder%'))
        OR (l.provider = 'b2b_enrichment' AND COALESCE(l.model_name, '') LIKE 'b2b-email_finder%')
      ) AS is_email_provider
    FROM labeled l
  ),
  metric_resolved AS (
    SELECT
      m.*,
      CASE
        WHEN m.found_emails_raw > 0 THEN m.found_emails_raw
        WHEN m.billable_units > 0 AND m.is_email_provider THEN m.billable_units
        ELSE 0
      END AS resolved_emails_found,
      CASE
        WHEN m.people_returned_raw > 0 THEN m.people_returned_raw
        WHEN m.is_people_search THEN m.generic_results
        ELSE 0
      END AS resolved_people_found,
      CASE
        WHEN m.companies_returned_raw > 0 THEN m.companies_returned_raw
        WHEN m.is_company_search THEN m.generic_results
        ELSE 0
      END AS resolved_companies_found
    FROM metric_inputs m
  ),
  metrics AS (
    SELECT
      r.*,
      CASE
        WHEN r.derived_category = 'phones' THEN COALESCE(NULLIF(r.phones_found_raw, 0), CASE WHEN r.is_success THEN 1 ELSE 0 END)
        ELSE 0
      END AS phones_found,
      CASE
        WHEN r.derived_category = 'b2b_data' THEN r.resolved_emails_found
        ELSE 0
      END AS emails_found,
      CASE
        WHEN r.derived_category = 'b2b_data' AND r.resolved_people_found > 0 AND NOT r.is_company_search THEN r.resolved_people_found
        WHEN r.derived_category = 'b2b_data'
          AND (r.resolved_emails_found + r.resolved_people_found + r.resolved_companies_found) = 0
          AND r.billable_units > 0
          AND r.is_people_search THEN r.billable_units
        ELSE 0
      END AS people_found,
      CASE
        WHEN r.derived_category = 'b2b_data' AND r.resolved_companies_found > 0 THEN r.resolved_companies_found
        WHEN r.derived_category = 'b2b_data'
          AND (r.resolved_emails_found + r.resolved_people_found + r.resolved_companies_found) = 0
          AND r.billable_units > 0
          AND r.is_company_search THEN r.billable_units
        WHEN r.derived_category = 'b2b_data'
          AND (r.resolved_emails_found + r.resolved_people_found + r.resolved_companies_found) = 0
          AND r.provider = 'b2b_enrichment'
          AND COALESCE(r.model_name, '') LIKE 'b2b-company_profile%' THEN COALESCE(NULLIF(r.billable_units, 0), 1)
        ELSE 0
      END AS companies_found
    FROM metric_resolved r
  )
  SELECT
    p_usage.id,
    m.organization_id,
    m.occurred_at,
    m.derived_category,
    COALESCE(m.campaign_id, ''),
    COALESCE(m.user_id, ''),
    m.derived_task_label,
    COALESCE(m.derived_model_label, ''),
    COALESCE(m.model_name, ''),
    COALESCE(m.service_name, ''),
    COALESCE(m.operation_name, ''),
    COALESCE(m.metadata ->> 'company_id', ''),
    COALESCE(m.run_id, ''),
    COALESCE(m.metadata ->> 'research_run_id', ''),
    m.api_calls::bigint,
    m.input_tokens::bigint,
    m.output_tokens::bigint,
    m.total_tokens::bigint,
    m.metadata_grounding_queries::bigint,
    CASE
      WHEN m.derived_category = 'phones' THEN m.phones_found
      WHEN m.derived_category = 'b2b_data' THEN m.emails_found + m.people_found + m.companies_found
      ELSE 0
    END,
    m.emails_found,
    m.people_found,
    m.companies_found,
    m.phones_found,
    m.original_cost,
    m.sellton_cost,
    now()
  FROM metrics m;
$function$;

CREATE OR REPLACE FUNCTION public.usage_display_category(p_category text, p_service_name text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE
    WHEN p_category = 'phones' THEN 'phone_numbers'
    WHEN p_category = 'b2b_data' AND p_service_name = 'retell' THEN 'research'
    WHEN p_category = 'tokens' AND COALESCE(p_service_name, '') IN (
      'email_generation_service',
      'email_generation',
      'hyper_personalized_email_service',
      'hyper_personalized_email',
      'linkedin_copywriter_service',
      'email_reply_processor_service',
      'email_reply_processor',
      'reply_handler_service',
      'email_intent_service',
      'security_guardrails_service',
      'deal_nurture_service',
      'call_pitch_service',
      'mobile_email_writing',
      'mobile_reply_handling'
    ) THEN 'writing'
    WHEN p_category = 'tokens' THEN 'research'
    ELSE 'company_data'
  END;
$function$;

CREATE OR REPLACE FUNCTION public.usage_provider_label(p_provider text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
  raw_value text := trim(COALESCE(p_provider, ''));
BEGIN
  CASE raw_value
    WHEN 'xai' THEN RETURN 'Advanced Research';
    WHEN 'grok' THEN RETURN 'Advanced Research';
    WHEN 'advanced_research' THEN RETURN 'Advanced Research';
    WHEN 'gemini_ultra_lean' THEN RETURN 'Gemini Ultra Lean';
    WHEN 'gemini_pro' THEN RETURN 'Gemini Pro Legacy';
    WHEN 'gemini' THEN RETURN 'Gemini';
    WHEN 'exa' THEN RETURN 'Exa';
    WHEN 'perplexity' THEN RETURN 'Perplexity';
    WHEN 'both' THEN RETURN 'Multi-provider';
    WHEN 'brain' THEN RETURN 'Sellton Brain';
    WHEN 'elevenlabs' THEN RETURN 'ElevenLabs';
    ELSE
      IF raw_value = '' THEN
        RETURN 'Unknown';
      END IF;
      RETURN initcap(regexp_replace(raw_value, '[_\s-]+', ' ', 'g'));
  END CASE;
END;
$function$;

INSERT INTO public.action_label_map (provider, service_name, model_name_pattern, requires_grounding, task_key, display_label, priority) VALUES
  ('', 'mobile_email_writing', '', false, 'email_copywriting', 'Email copywriting', 1),
  ('', 'mobile_reply_handling', '', false, 'email_reply_handling', 'Email reply handling', 1),
  ('', 'mobile_assistant', '', false, 'mobile_assistant', 'Sellton assistant', 1),
  ('', 'mobile_company_search', '', false, 'company_research', 'Company research', 1),
  ('', 'mobile_people_search', '', false, 'contact_enrichment', 'Contact enrichment', 1),
  ('', 'mobile_phone_discovery', '', false, 'phone_discovery', 'Phone discovery', 1),
  ('', 'mobile_signals', '', false, 'signals', 'Signals', 1),
  ('', 'mobile_card_reading', '', false, 'card_reading', 'Business card reading', 1),
  ('', 'mobile_voice', '', false, 'voice', 'Sellton voice', 1)
ON CONFLICT (provider, service_name, model_name_pattern, requires_grounding, task_key) DO UPDATE SET display_label = EXCLUDED.display_label, priority = EXCLUDED.priority;

CREATE OR REPLACE FUNCTION public.analytics_usage_rollup_v5(p_org_id text, p_start timestamp with time zone, p_end timestamp with time zone, p_bucket text DEFAULT 'total'::text, p_campaign_id text DEFAULT NULL::text, p_user_id text DEFAULT NULL::text, p_app text DEFAULT NULL::text)
 RETURNS TABLE(bucket_start timestamp with time zone, display_category text, api_calls bigint, input_tokens bigint, output_tokens bigint, total_tokens bigint, units numeric, emails_found numeric, people_found numeric, companies_found numeric, phones_found numeric, sellton_cost numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF p_bucket IS NULL OR p_bucket NOT IN ('hour', 'day', 'total') THEN
    RAISE EXCEPTION 'unsupported usage analytics bucket %', p_bucket;
  END IF;

  IF p_app IS NOT NULL AND p_app NOT IN ('mobile', 'web') THEN
    RAISE EXCEPTION 'unsupported usage analytics app %', p_app;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.usage_analytics_projection_state
    WHERE singleton
      AND historical_backfill_completed_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'USAGE_ANALYTICS_PROJECTION_NOT_READY';
  END IF;

  RETURN QUERY
  WITH scope AS (
    SELECT
      CASE WHEN p_bucket = 'hour' THEN 'hour'::text ELSE 'day'::text END AS bucket_granularity,
      CASE WHEN p_bucket = 'hour' THEN interval '1 hour' ELSE interval '1 day' END AS bucket_width
  ),
  -- Whole buckets inside the window come from the projection (as v3).
  projection_rows AS (
    SELECT
      rollup.bucket_start AS source_bucket_start,
      rollup.category,
      rollup.service_name,
      rollup.campaign_id,
      rollup.user_id,
      rollup.api_calls,
      rollup.input_tokens,
      rollup.output_tokens,
      rollup.total_tokens,
      rollup.units,
      rollup.emails_found,
      rollup.people_found,
      rollup.companies_found,
      rollup.phones_found,
      rollup.original_cost,
      rollup.sellton_cost
    FROM public.usage_analytics_projection_rollups rollup
    CROSS JOIN scope
    WHERE rollup.organization_id = p_org_id
      AND rollup.bucket_granularity = scope.bucket_granularity
      AND rollup.bucket_start >= p_start
      AND rollup.bucket_start + scope.bucket_width <= p_end
  ),
  -- Partial buckets at the window's edges come from the per-row contributions (as v3), grouped by the projection's
  -- own key so that the $0 rule below sees the same groups on an edge as on a whole bucket.
  edge_rows AS (
    SELECT
      edge.source_bucket_start,
      edge.category,
      edge.service_name,
      edge.campaign_id,
      edge.user_id,
      SUM(edge.api_calls)::bigint,
      SUM(edge.input_tokens)::bigint,
      SUM(edge.output_tokens)::bigint,
      SUM(edge.total_tokens)::bigint,
      SUM(edge.units),
      SUM(edge.emails_found),
      SUM(edge.people_found),
      SUM(edge.companies_found),
      SUM(edge.phones_found),
      SUM(edge.original_cost),
      SUM(edge.sellton_cost)
    FROM (
      SELECT
        date_trunc(scope.bucket_granularity, contribution.occurred_at AT TIME ZONE 'UTC') AT TIME ZONE 'UTC' AS source_bucket_start,
        scope.bucket_width,
        contribution.*
      FROM public.usage_analytics_projection_contributions contribution
      CROSS JOIN scope
      WHERE contribution.organization_id = p_org_id
        AND contribution.occurred_at >= p_start
        AND contribution.occurred_at <= p_end
    ) edge
    WHERE NOT (
      edge.source_bucket_start >= p_start
      AND edge.source_bucket_start + edge.bucket_width <= p_end
    )
    GROUP BY
      edge.source_bucket_start, edge.category, edge.campaign_id, edge.user_id, edge.task_label, edge.model_label,
      edge.raw_model_name, edge.service_name, edge.operation_name, edge.company_id, edge.run_id,
      edge.metadata_research_run_id
  ),
  scoped AS (
    SELECT
      CASE
        WHEN p_bucket = 'total' THEN date_trunc('day', p_start AT TIME ZONE 'UTC') AT TIME ZONE 'UTC'
        ELSE base_rows.source_bucket_start
      END AS grouped_bucket_start,
      public.usage_display_category(base_rows.category, base_rows.service_name) AS grouped_category,
      base_rows.*
    FROM (
      SELECT * FROM projection_rows
      UNION ALL
      SELECT * FROM edge_rows
    ) base_rows
    WHERE (NULLIF(p_campaign_id, '') IS NULL OR p_campaign_id = 'all' OR base_rows.campaign_id = p_campaign_id)
      AND (NULLIF(p_user_id, '') IS NULL OR base_rows.user_id = p_user_id)
      -- v5: 'mobile' is the phone's usage (services named mobile_*), 'web' everything else, NULL both (= v4).
      AND (p_app IS NULL OR (p_app = 'mobile') = (COALESCE(base_rows.service_name, '') LIKE 'mobile\_%'))
      -- $0 infrastructure groups (company data with no cost at all and no tokens) are hidden, calls and counts included.
      AND NOT (
        public.usage_display_category(base_rows.category, base_rows.service_name) = 'company_data'
        AND base_rows.sellton_cost = 0
        AND base_rows.original_cost = 0
        AND base_rows.total_tokens = 0
      )
  )
  SELECT
    scoped.grouped_bucket_start,
    scoped.grouped_category,
    SUM(scoped.api_calls)::bigint,
    SUM(scoped.input_tokens)::bigint,
    SUM(scoped.output_tokens)::bigint,
    SUM(scoped.total_tokens)::bigint,
    SUM(scoped.units),
    SUM(scoped.emails_found),
    SUM(scoped.people_found),
    SUM(scoped.companies_found),
    SUM(scoped.phones_found),
    ROUND(SUM(scoped.sellton_cost), 6)
  FROM scoped
  GROUP BY scoped.grouped_bucket_start, scoped.grouped_category
  ORDER BY scoped.grouped_bucket_start ASC, SUM(scoped.sellton_cost) DESC, scoped.grouped_category;
END;
$function$;

COMMENT ON FUNCTION public.analytics_usage_rollup_v5(text, timestamptz, timestamptz, text, text, text, text) IS
  'KAN-333 X1: analytics_usage_rollup_v4 plus p_app: ''mobile'' sums the phone''s usage (metadata.service mobile_*), '
  '''web'' everything else, NULL both (equal to v4). Read by the mobile service with the service role.';

REVOKE ALL ON FUNCTION public.analytics_usage_rollup_v5(text, timestamptz, timestamptz, text, text, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.analytics_usage_rollup_v5(text, timestamptz, timestamptz, text, text, text, text) TO service_role;

-- Verify (read-only):
--   SELECT public.usage_display_category('tokens', 'mobile_email_writing'),  -- writing
--          public.usage_provider_label('brain'), public.usage_provider_label('elevenlabs');  -- Sellton Brain, ElevenLabs
--   SELECT count(*) FROM public.action_label_map WHERE service_name LIKE 'mobile\_%';  -- 9
--   -- v5 with NULL equals v4 for the same window:
--   SELECT * FROM public.analytics_usage_rollup_v4('<org_id>', now() - interval '30 days', now())
--   EXCEPT SELECT * FROM public.analytics_usage_rollup_v5('<org_id>', now() - interval '30 days', now());  -- no rows
--   SELECT has_function_privilege('anon', 'public.analytics_usage_rollup_v5(text,timestamptz,timestamptz,text,text,text,text)', 'EXECUTE');  -- f
