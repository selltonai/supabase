-- Reverses 438. Deploy the Modal and app commits that stop using the Strategy tab first (the routes and the daily cron read
-- and write these tables and fail while they are gone). Lossy: every strategy, play and suggestion goes with the tables, and
-- the notifications of type strategy_ready and strategy_suggestion are deleted (the CHECK cannot hold them without the two
-- values). Campaigns created from a play stay (the link is on the play row only). Usage rows already written keep their
-- projection until projected again.
SET LOCAL lock_timeout = '10s';

DROP TABLE IF EXISTS public.gtm_strategy_suggestions;
DROP TABLE IF EXISTS public.gtm_strategy_plays;
DROP TABLE IF EXISTS public.gtm_strategies;

DELETE FROM public.notifications WHERE type IN ('strategy_ready', 'strategy_suggestion');

-- Take the two values out of the installed CHECK: the expression is read and the two clauses 438 appended are cut out
-- (a clause deparses as `(type = 'x'::text)` or `((type)::text = 'x'::text)`). If any trace is left the migration stops.
DO $$
DECLARE v_expression text;
BEGIN
  SELECT pg_get_expr(conbin, conrelid) INTO STRICT v_expression
  FROM pg_constraint WHERE conrelid = 'public.notifications'::regclass
    AND conname = 'notifications_type_check';
  IF position('strategy_' IN v_expression) > 0 THEN
    v_expression := regexp_replace(
      v_expression,
      '\s+OR\s+\(\(?type\)?(::text)?\s*=\s*''strategy_(ready|suggestion)''::text\)',
      '',
      'g');
    IF position('strategy_' IN v_expression) > 0 THEN
      RAISE EXCEPTION 'rollback 438: could not take strategy_ready and strategy_suggestion out of notifications_type_check';
    END IF;
    ALTER TABLE public.notifications DROP CONSTRAINT notifications_type_check;
    EXECUTE 'ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check CHECK (' || v_expression || ')';
  END IF;
END $$;

-- 431's function text back byte for byte (no Strategy label, no strategy unit).
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
        -- 431: Brain signals of the web app
        WHEN c.service_name IN ('brain_signals', 'brain_signal_router') THEN 'Signals'
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
      WHEN m.derived_category = 'b2b_data' AND m.service_name = 'brain_signals' THEN 1
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

DELETE FROM public.action_label_map
WHERE provider = '' AND model_name_pattern = '' AND requires_grounding = false AND task_key = 'strategy'
  AND service_name = 'gtm_strategy';
