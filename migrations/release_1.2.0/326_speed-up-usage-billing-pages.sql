-- Speed up usage and billing pages for large workspaces.
--
-- What changed:
--   - Adds DB-side helpers for normalized usage metadata.
--   - Adds analytics_usage_rollup_v2(), a server-side aggregation used by
--     selltonai /api/analytics/usage-rollup.
--   - Avoids transferring and grouping every raw public.usage row in Next.js.
--
-- Projects depending on this:
--   - selltonai reads analytics_usage_rollup_v2() for Usage Analytics.
--   - selltonai-modal keeps writing public.usage rows with the same shape.
--   - backoffice may continue reading public.usage directly; no contract change.
--
-- Application code update:
--   - Deploy with selltonai usage-rollup route update.
--   - Response shape remains unchanged: data[] rows plus summary totals.

CREATE OR REPLACE FUNCTION public.usage_metadata_object(p_metadata jsonb)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  current_value jsonb := p_metadata;
  raw_text text;
BEGIN
  IF current_value IS NULL THEN
    RETURN '{}'::jsonb;
  END IF;

  FOR i IN 1..3 LOOP
    IF jsonb_typeof(current_value) = 'object' THEN
      RETURN current_value;
    END IF;

    IF jsonb_typeof(current_value) <> 'string' THEN
      RETURN '{}'::jsonb;
    END IF;

    raw_text := current_value #>> '{}';
    BEGIN
      current_value := raw_text::jsonb;
    EXCEPTION WHEN others THEN
      RETURN '{}'::jsonb;
    END;
  END LOOP;

  IF jsonb_typeof(current_value) = 'object' THEN
    RETURN current_value;
  END IF;

  RETURN '{}'::jsonb;
END;
$$;

CREATE OR REPLACE FUNCTION public.usage_metadata_number(p_metadata jsonb, p_key text)
RETURNS numeric
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  value jsonb;
  raw_text text;
BEGIN
  IF p_metadata IS NULL OR NOT (p_metadata ? p_key) THEN
    RETURN 0;
  END IF;

  value := p_metadata -> p_key;
  raw_text := value #>> '{}';

  IF raw_text ~ '^\s*-?\d+(\.\d+)?\s*$' THEN
    RETURN raw_text::numeric;
  END IF;

  RETURN 0;
END;
$$;

CREATE OR REPLACE FUNCTION public.usage_metadata_boolean(p_metadata jsonb, p_key text)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  value jsonb;
  raw_text text;
BEGIN
  IF p_metadata IS NULL OR NOT (p_metadata ? p_key) THEN
    RETURN false;
  END IF;

  value := p_metadata -> p_key;
  IF jsonb_typeof(value) = 'boolean' THEN
    RETURN (value #>> '{}')::boolean;
  END IF;

  raw_text := lower(trim(value #>> '{}'));
  RETURN raw_text IN ('true', '1', 'yes');
END;
$$;

CREATE OR REPLACE FUNCTION public.usage_metadata_count(p_metadata jsonb, VARIADIC p_keys text[])
RETURNS numeric
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  key_name text;
  value jsonb;
  raw_text text;
  nested_count numeric;
BEGIN
  IF p_metadata IS NULL THEN
    RETURN 0;
  END IF;

  FOREACH key_name IN ARRAY p_keys LOOP
    IF NOT (p_metadata ? key_name) THEN
      CONTINUE;
    END IF;

    value := p_metadata -> key_name;

    IF jsonb_typeof(value) = 'array' THEN
      IF jsonb_array_length(value) > 0 THEN
        RETURN jsonb_array_length(value);
      END IF;
      CONTINUE;
    END IF;

    IF jsonb_typeof(value) = 'object' THEN
      nested_count := public.usage_metadata_count(value, VARIADIC ARRAY['count', 'total', 'length']);
      IF nested_count > 0 THEN
        RETURN nested_count;
      END IF;
      CONTINUE;
    END IF;

    raw_text := value #>> '{}';
    IF raw_text ~ '^\s*-?\d+(\.\d+)?\s*$' THEN
      IF raw_text::numeric > 0 THEN
        RETURN raw_text::numeric;
      END IF;
      CONTINUE;
    END IF;

    IF trim(COALESCE(raw_text, '')) <> '' THEN
      RETURN 1;
    END IF;
  END LOOP;

  RETURN 0;
END;
$$;

CREATE OR REPLACE FUNCTION public.usage_provider_label(p_provider text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
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
    ELSE
      IF raw_value = '' THEN
        RETURN 'Unknown';
      END IF;
      RETURN initcap(regexp_replace(raw_value, '[_\s-]+', ' ', 'g'));
  END CASE;
END;
$$;

CREATE OR REPLACE FUNCTION public.analytics_usage_rollup_v2(
  p_org_id text,
  p_start timestamptz,
  p_end timestamptz,
  p_bucket text DEFAULT 'day',
  p_category text DEFAULT NULL,
  p_campaign_id text DEFAULT NULL,
  p_model_name text DEFAULT NULL,
  p_user_id text DEFAULT NULL,
  p_service_name text DEFAULT NULL,
  p_operation text DEFAULT NULL,
  p_company_id text DEFAULT NULL,
  p_research_run_id text DEFAULT NULL
)
RETURNS TABLE (
  bucket_start timestamptz,
  category text,
  campaign_id text,
  user_id text,
  task_label text,
  model_label text,
  api_calls bigint,
  input_tokens bigint,
  output_tokens bigint,
  total_tokens bigint,
  grounding_queries bigint,
  units numeric,
  emails_found numeric,
  people_found numeric,
  companies_found numeric,
  phones_found numeric,
  original_cost numeric,
  sellton_cost numeric
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH base_usage AS (
    SELECT
      CASE
        WHEN p_bucket = 'hour' THEN date_trunc('hour', u.created_at)
        WHEN p_bucket = 'day' THEN date_trunc('day', u.created_at)
        ELSE date_trunc('day', p_start)
      END AS bucket_start,
      u.provider,
      u.model_name,
      u.campaign_id,
      u.user_id,
      u.run_id,
      COALESCE(u.api_calls, 0)::numeric AS api_calls,
      COALESCE(u.input_tokens, 0)::numeric AS input_tokens,
      COALESCE(u.output_tokens, 0)::numeric AS output_tokens,
      (
        CASE
          WHEN COALESCE(u.total_tokens, 0) > 0 THEN COALESCE(u.total_tokens, 0)
          ELSE COALESCE(u.input_tokens, 0) + COALESCE(u.output_tokens, 0)
        END
      )::numeric AS total_tokens,
      COALESCE(u.original_cost, 0)::numeric AS original_cost,
      COALESCE(u.sellton_cost, 0)::numeric AS sellton_cost,
      md.metadata
    FROM public.usage u
    CROSS JOIN LATERAL (
      SELECT public.usage_metadata_object(u.metadata) AS metadata
    ) md
    WHERE u.organization_id = p_org_id
      AND u.created_at >= p_start
      AND u.created_at <= p_end
      AND (NULLIF(p_campaign_id, '') IS NULL OR p_campaign_id = 'all' OR u.campaign_id = p_campaign_id)
      AND (NULLIF(p_model_name, '') IS NULL OR p_model_name = 'all' OR u.model_name = p_model_name)
      AND (NULLIF(p_user_id, '') IS NULL OR u.user_id = p_user_id)
      AND (
        NULLIF(p_research_run_id, '') IS NULL
        OR u.run_id = p_research_run_id
        OR md.metadata ->> 'research_run_id' = p_research_run_id
      )
      AND (NULLIF(p_service_name, '') IS NULL OR md.metadata ->> 'service' = p_service_name)
      AND (NULLIF(p_operation, '') IS NULL OR md.metadata ->> 'operation' = p_operation)
      AND (NULLIF(p_company_id, '') IS NULL OR md.metadata ->> 'company_id' = p_company_id)
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
      CASE
        WHEN b.provider = 'airscale'
          AND (
            COALESCE(b.metadata ->> 'action', '') = 'phone_finder'
            OR COALESCE(b.model_name, '') LIKE 'airscale-phone%'
          ) THEN 'phones'
        WHEN b.provider IN ('openai', 'anthropic', 'deepseek', 'togetherai', 'perplexity', 'gemini', 'mistral', 'xai', 'grok') THEN 'tokens'
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
    WHERE (NULLIF(p_category, '') IS NULL OR c.derived_category = p_category)
  ),
  metric_inputs AS (
    SELECT
      l.*,
      public.usage_metadata_count(
        l.metadata,
        VARIADIC ARRAY[
          'found_emails',
          'emails_found',
          'email_matches',
          'returned_email_matches',
          'returned_emails',
          'emails_returned',
          'emails',
          'email_found',
          'found_email',
          'email'
        ]
      ) AS found_emails_raw,
      public.usage_metadata_count(
        l.metadata,
        VARIADIC ARRAY[
          'profiles_returned',
          'people_found',
          'people_returned',
          'returned_people',
          'returned_profiles',
          'profile_count',
          'profiles_found',
          'results_found'
        ]
      ) AS people_returned_raw,
      public.usage_metadata_count(
        l.metadata,
        VARIADIC ARRAY[
          'companies_found',
          'companies_returned',
          'returned_companies',
          'company_count',
          'company_profiles_returned',
          'similar_companies'
        ]
      ) AS companies_returned_raw,
      public.usage_metadata_count(l.metadata, VARIADIC ARRAY['results', 'items', 'data']) AS generic_results,
      public.usage_metadata_count(
        l.metadata,
        VARIADIC ARRAY[
          'phones_found',
          'phone_found',
          'phone_number',
          'phone_numbers',
          'phone',
          'phones',
          'mobile_phone',
          'mobile'
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
      r.bucket_start,
      r.derived_category,
      r.campaign_id,
      r.user_id,
      r.derived_task_label,
      r.derived_model_label,
      r.api_calls,
      r.input_tokens,
      r.output_tokens,
      r.total_tokens,
      r.metadata_grounding_queries,
      r.original_cost,
      r.sellton_cost,
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
    m.bucket_start,
    m.derived_category AS category,
    m.campaign_id,
    m.user_id,
    m.derived_task_label AS task_label,
    m.derived_model_label AS model_label,
    SUM(m.api_calls)::bigint AS api_calls,
    SUM(m.input_tokens)::bigint AS input_tokens,
    SUM(m.output_tokens)::bigint AS output_tokens,
    SUM(m.total_tokens)::bigint AS total_tokens,
    SUM(m.metadata_grounding_queries)::bigint AS grounding_queries,
    SUM(
      CASE
        WHEN m.derived_category = 'phones' THEN m.phones_found
        WHEN m.derived_category = 'b2b_data' THEN m.emails_found + m.people_found + m.companies_found
        ELSE 0
      END
    ) AS units,
    SUM(m.emails_found) AS emails_found,
    SUM(m.people_found) AS people_found,
    SUM(m.companies_found) AS companies_found,
    SUM(m.phones_found) AS phones_found,
    ROUND(SUM(m.original_cost), 6) AS original_cost,
    ROUND(SUM(m.sellton_cost), 6) AS sellton_cost
  FROM metrics m
  GROUP BY
    m.bucket_start,
    m.derived_category,
    m.campaign_id,
    m.user_id,
    m.derived_task_label,
    m.derived_model_label
  ORDER BY
    m.bucket_start ASC,
    SUM(m.sellton_cost) DESC,
    m.derived_category,
    m.derived_task_label,
    m.derived_model_label;
$$;

COMMENT ON FUNCTION public.analytics_usage_rollup_v2(text, timestamptz, timestamptz, text, text, text, text, text, text, text, text, text)
  IS 'Fast server-side rollup for selltonai Usage Analytics. Preserves the /api/analytics/usage-rollup response fields.';

GRANT EXECUTE ON FUNCTION public.analytics_usage_rollup_v2(text, timestamptz, timestamptz, text, text, text, text, text, text, text, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.usage_metadata_object(jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.usage_metadata_number(jsonb, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.usage_metadata_boolean(jsonb, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.usage_metadata_count(jsonb, text[]) TO service_role;
GRANT EXECUTE ON FUNCTION public.usage_provider_label(text) TO service_role;
