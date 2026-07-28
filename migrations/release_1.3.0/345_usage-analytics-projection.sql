-- 345 — Durable Usage Analytics projection.
--
-- What changed:
--   - Adds a trigger-maintained hourly/daily projection for Usage Analytics.
--   - Keeps one normalized contribution per source usage row so updates and
--     deletes apply exact deltas to the aggregate rather than drifting.
--   - Adds analytics_usage_rollup_v3(), preserving the v2 result shape while
--     reading only the projection after historical backfill is complete.
--
-- Affected projects:
--   - selltonai must switch /api/analytics/usage-rollup to v3 only after the
--     bounded historical backfill is complete.
--   - selltonai-modal keeps writing public.usage with its existing contract;
--     the database trigger maintains the projection transactionally.
--   - backoffice and billing readers are unchanged.
--
-- Deployment order:
--   1. Apply this additive migration.
--   2. Repeatedly call backfill_usage_analytics_projection() in bounded
--      batches until no row is returned.
--   3. Call complete_usage_analytics_projection_backfill().
--   4. Deploy the selltonai route change to analytics_usage_rollup_v3().
--
-- Rollback safety:
--   Before step 4, the application remains on v2. The v3 function refuses
--   reads while the historical projection is incomplete, rather than serving
--   partial results or falling back to an unbounded raw scan.

CREATE TABLE IF NOT EXISTS public.usage_analytics_projection_rollups (
  organization_id text NOT NULL,
  bucket_granularity text NOT NULL CHECK (bucket_granularity IN ('hour', 'day')),
  bucket_start timestamptz NOT NULL,
  category text NOT NULL CHECK (category IN ('tokens', 'b2b_data', 'phones')),
  campaign_id text NOT NULL DEFAULT '',
  user_id text NOT NULL DEFAULT '',
  task_label text NOT NULL,
  model_label text NOT NULL DEFAULT '',
  raw_model_name text NOT NULL DEFAULT '',
  service_name text NOT NULL DEFAULT '',
  operation_name text NOT NULL DEFAULT '',
  company_id text NOT NULL DEFAULT '',
  run_id text NOT NULL DEFAULT '',
  metadata_research_run_id text NOT NULL DEFAULT '',
  api_calls bigint NOT NULL DEFAULT 0,
  input_tokens bigint NOT NULL DEFAULT 0,
  output_tokens bigint NOT NULL DEFAULT 0,
  total_tokens bigint NOT NULL DEFAULT 0,
  grounding_queries bigint NOT NULL DEFAULT 0,
  units numeric NOT NULL DEFAULT 0,
  emails_found numeric NOT NULL DEFAULT 0,
  people_found numeric NOT NULL DEFAULT 0,
  companies_found numeric NOT NULL DEFAULT 0,
  phones_found numeric NOT NULL DEFAULT 0,
  original_cost numeric NOT NULL DEFAULT 0,
  sellton_cost numeric NOT NULL DEFAULT 0,
  usage_row_count bigint NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (
    organization_id,
    bucket_granularity,
    bucket_start,
    category,
    campaign_id,
    user_id,
    task_label,
    model_label,
    raw_model_name,
    service_name,
    operation_name,
    company_id,
    run_id,
    metadata_research_run_id
  )
);

-- A delta is first presented as an INSERT and may have a negative row count
-- before ON CONFLICT merges it with the existing aggregate. The invariant is
-- checked in apply_usage_analytics_projection_delta() after that merge.
ALTER TABLE public.usage_analytics_projection_rollups
  DROP CONSTRAINT IF EXISTS usage_analytics_projection_rollups_usage_row_count_check;

CREATE TABLE IF NOT EXISTS public.usage_analytics_projection_contributions (
  usage_id uuid PRIMARY KEY REFERENCES public.usage(id) ON DELETE CASCADE,
  organization_id text NOT NULL,
  occurred_at timestamptz NOT NULL,
  category text NOT NULL CHECK (category IN ('tokens', 'b2b_data', 'phones')),
  campaign_id text NOT NULL DEFAULT '',
  user_id text NOT NULL DEFAULT '',
  task_label text NOT NULL,
  model_label text NOT NULL DEFAULT '',
  raw_model_name text NOT NULL DEFAULT '',
  service_name text NOT NULL DEFAULT '',
  operation_name text NOT NULL DEFAULT '',
  company_id text NOT NULL DEFAULT '',
  run_id text NOT NULL DEFAULT '',
  metadata_research_run_id text NOT NULL DEFAULT '',
  api_calls bigint NOT NULL,
  input_tokens bigint NOT NULL,
  output_tokens bigint NOT NULL,
  total_tokens bigint NOT NULL,
  grounding_queries bigint NOT NULL,
  units numeric NOT NULL,
  emails_found numeric NOT NULL,
  people_found numeric NOT NULL,
  companies_found numeric NOT NULL,
  phones_found numeric NOT NULL,
  original_cost numeric NOT NULL,
  sellton_cost numeric NOT NULL,
  projected_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_usage_analytics_projection_contributions_org_occurred
  ON public.usage_analytics_projection_contributions (organization_id, occurred_at);

CREATE TABLE IF NOT EXISTS public.usage_analytics_projection_state (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  historical_backfill_completed_at timestamptz
);

INSERT INTO public.usage_analytics_projection_state (singleton)
VALUES (true)
ON CONFLICT (singleton) DO NOTHING;

ALTER TABLE public.usage_analytics_projection_rollups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.usage_analytics_projection_contributions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.usage_analytics_projection_state ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.usage_analytics_projection_rollups FROM anon, authenticated;
REVOKE ALL ON TABLE public.usage_analytics_projection_contributions FROM anon, authenticated;
REVOKE ALL ON TABLE public.usage_analytics_projection_state FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.usage_analytics_projection_contribution(p_usage public.usage)
RETURNS SETOF public.usage_analytics_projection_contributions
LANGUAGE sql
STABLE
SET search_path = public
AS $$
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
$$;

CREATE OR REPLACE FUNCTION public.apply_usage_analytics_projection_delta(
  p_contribution public.usage_analytics_projection_contributions,
  p_multiplier integer
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  projection_bucket record;
BEGIN
  IF p_multiplier NOT IN (-1, 1) THEN
    RAISE EXCEPTION 'usage analytics projection multiplier must be -1 or 1';
  END IF;

  FOR projection_bucket IN
    SELECT
      'hour'::text AS bucket_granularity,
      date_trunc('hour', p_contribution.occurred_at AT TIME ZONE 'UTC') AT TIME ZONE 'UTC' AS bucket_start
    UNION ALL
    SELECT
      'day'::text AS bucket_granularity,
      date_trunc('day', p_contribution.occurred_at AT TIME ZONE 'UTC') AT TIME ZONE 'UTC' AS bucket_start
  LOOP
    INSERT INTO public.usage_analytics_projection_rollups (
      organization_id, bucket_granularity, bucket_start, category, campaign_id,
      user_id, task_label, model_label, raw_model_name, service_name,
      operation_name, company_id, run_id, metadata_research_run_id, api_calls,
      input_tokens, output_tokens, total_tokens, grounding_queries, units,
      emails_found, people_found, companies_found, phones_found, original_cost,
      sellton_cost, usage_row_count
    )
    VALUES (
      p_contribution.organization_id,
      projection_bucket.bucket_granularity,
      projection_bucket.bucket_start,
      p_contribution.category,
      p_contribution.campaign_id,
      p_contribution.user_id,
      p_contribution.task_label,
      p_contribution.model_label,
      p_contribution.raw_model_name,
      p_contribution.service_name,
      p_contribution.operation_name,
      p_contribution.company_id,
      p_contribution.run_id,
      p_contribution.metadata_research_run_id,
      p_contribution.api_calls * p_multiplier,
      p_contribution.input_tokens * p_multiplier,
      p_contribution.output_tokens * p_multiplier,
      p_contribution.total_tokens * p_multiplier,
      p_contribution.grounding_queries * p_multiplier,
      p_contribution.units * p_multiplier,
      p_contribution.emails_found * p_multiplier,
      p_contribution.people_found * p_multiplier,
      p_contribution.companies_found * p_multiplier,
      p_contribution.phones_found * p_multiplier,
      p_contribution.original_cost * p_multiplier,
      p_contribution.sellton_cost * p_multiplier,
      p_multiplier
    )
    ON CONFLICT (
      organization_id, bucket_granularity, bucket_start, category, campaign_id,
      user_id, task_label, model_label, raw_model_name, service_name,
      operation_name, company_id, run_id, metadata_research_run_id
    ) DO UPDATE
    SET
      api_calls = public.usage_analytics_projection_rollups.api_calls + EXCLUDED.api_calls,
      input_tokens = public.usage_analytics_projection_rollups.input_tokens + EXCLUDED.input_tokens,
      output_tokens = public.usage_analytics_projection_rollups.output_tokens + EXCLUDED.output_tokens,
      total_tokens = public.usage_analytics_projection_rollups.total_tokens + EXCLUDED.total_tokens,
      grounding_queries = public.usage_analytics_projection_rollups.grounding_queries + EXCLUDED.grounding_queries,
      units = public.usage_analytics_projection_rollups.units + EXCLUDED.units,
      emails_found = public.usage_analytics_projection_rollups.emails_found + EXCLUDED.emails_found,
      people_found = public.usage_analytics_projection_rollups.people_found + EXCLUDED.people_found,
      companies_found = public.usage_analytics_projection_rollups.companies_found + EXCLUDED.companies_found,
      phones_found = public.usage_analytics_projection_rollups.phones_found + EXCLUDED.phones_found,
      original_cost = public.usage_analytics_projection_rollups.original_cost + EXCLUDED.original_cost,
      sellton_cost = public.usage_analytics_projection_rollups.sellton_cost + EXCLUDED.sellton_cost,
      usage_row_count = public.usage_analytics_projection_rollups.usage_row_count + EXCLUDED.usage_row_count,
      updated_at = now();

    DELETE FROM public.usage_analytics_projection_rollups
    WHERE organization_id = p_contribution.organization_id
      AND bucket_granularity = projection_bucket.bucket_granularity
      AND bucket_start = projection_bucket.bucket_start
      AND category = p_contribution.category
      AND campaign_id = p_contribution.campaign_id
      AND user_id = p_contribution.user_id
      AND task_label = p_contribution.task_label
      AND model_label = p_contribution.model_label
      AND raw_model_name = p_contribution.raw_model_name
      AND service_name = p_contribution.service_name
      AND operation_name = p_contribution.operation_name
      AND company_id = p_contribution.company_id
      AND run_id = p_contribution.run_id
      AND metadata_research_run_id = p_contribution.metadata_research_run_id
      AND usage_row_count = 0;

    IF EXISTS (
      SELECT 1
      FROM public.usage_analytics_projection_rollups
      WHERE organization_id = p_contribution.organization_id
        AND bucket_granularity = projection_bucket.bucket_granularity
        AND bucket_start = projection_bucket.bucket_start
        AND category = p_contribution.category
        AND campaign_id = p_contribution.campaign_id
        AND user_id = p_contribution.user_id
        AND task_label = p_contribution.task_label
        AND model_label = p_contribution.model_label
        AND raw_model_name = p_contribution.raw_model_name
        AND service_name = p_contribution.service_name
        AND operation_name = p_contribution.operation_name
        AND company_id = p_contribution.company_id
        AND run_id = p_contribution.run_id
        AND metadata_research_run_id = p_contribution.metadata_research_run_id
        AND usage_row_count < 0
    ) THEN
      RAISE EXCEPTION 'usage analytics projection subtraction has no matching aggregate for usage_id %', p_contribution.usage_id;
    END IF;
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_usage_analytics_projection()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  previous_contribution public.usage_analytics_projection_contributions;
  next_contribution public.usage_analytics_projection_contributions;
  stored_contribution public.usage_analytics_projection_contributions;
BEGIN
  IF TG_OP = 'UPDATE' AND NEW IS NOT DISTINCT FROM OLD THEN
    RETURN NEW;
  END IF;

  IF TG_OP IN ('UPDATE', 'DELETE') THEN
    SELECT *
    INTO previous_contribution
    FROM public.usage_analytics_projection_contributions
    WHERE usage_id = OLD.id
    FOR UPDATE;

    IF FOUND THEN
      PERFORM public.apply_usage_analytics_projection_delta(previous_contribution, -1);
      DELETE FROM public.usage_analytics_projection_contributions
      WHERE usage_id = OLD.id;
    END IF;
  END IF;

  IF TG_OP IN ('INSERT', 'UPDATE') THEN
    SELECT *
    INTO next_contribution
    FROM public.usage_analytics_projection_contribution(NEW);

    IF NOT FOUND THEN
      RETURN NEW;
    END IF;

    LOOP
      INSERT INTO public.usage_analytics_projection_contributions (
        usage_id, organization_id, occurred_at, category, campaign_id, user_id,
        task_label, model_label, raw_model_name, service_name, operation_name,
        company_id, run_id, metadata_research_run_id, api_calls, input_tokens,
        output_tokens, total_tokens, grounding_queries, units, emails_found,
        people_found, companies_found, phones_found, original_cost, sellton_cost,
        projected_at
      )
      VALUES (
        next_contribution.usage_id,
        next_contribution.organization_id,
        next_contribution.occurred_at,
        next_contribution.category,
        next_contribution.campaign_id,
        next_contribution.user_id,
        next_contribution.task_label,
        next_contribution.model_label,
        next_contribution.raw_model_name,
        next_contribution.service_name,
        next_contribution.operation_name,
        next_contribution.company_id,
        next_contribution.run_id,
        next_contribution.metadata_research_run_id,
        next_contribution.api_calls,
        next_contribution.input_tokens,
        next_contribution.output_tokens,
        next_contribution.total_tokens,
        next_contribution.grounding_queries,
        next_contribution.units,
        next_contribution.emails_found,
        next_contribution.people_found,
        next_contribution.companies_found,
        next_contribution.phones_found,
        next_contribution.original_cost,
        next_contribution.sellton_cost,
        next_contribution.projected_at
      )
      ON CONFLICT (usage_id) DO NOTHING
      RETURNING * INTO stored_contribution;

      EXIT WHEN FOUND;

      SELECT *
      INTO previous_contribution
      FROM public.usage_analytics_projection_contributions
      WHERE usage_id = NEW.id
      FOR UPDATE;

      IF NOT FOUND THEN
        RAISE EXCEPTION 'usage analytics projection contribution disappeared for usage_id %', NEW.id;
      END IF;

      PERFORM public.apply_usage_analytics_projection_delta(previous_contribution, -1);
      DELETE FROM public.usage_analytics_projection_contributions
      WHERE usage_id = NEW.id;
    END LOOP;

    PERFORM public.apply_usage_analytics_projection_delta(stored_contribution, 1);
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS usage_analytics_projection_after_insert ON public.usage;
CREATE TRIGGER usage_analytics_projection_after_insert
AFTER INSERT ON public.usage
FOR EACH ROW
EXECUTE FUNCTION public.sync_usage_analytics_projection();

DROP TRIGGER IF EXISTS usage_analytics_projection_before_update ON public.usage;
CREATE TRIGGER usage_analytics_projection_before_update
BEFORE UPDATE ON public.usage
FOR EACH ROW
EXECUTE FUNCTION public.sync_usage_analytics_projection();

DROP TRIGGER IF EXISTS usage_analytics_projection_before_delete ON public.usage;
CREATE TRIGGER usage_analytics_projection_before_delete
BEFORE DELETE ON public.usage
FOR EACH ROW
EXECUTE FUNCTION public.sync_usage_analytics_projection();

CREATE OR REPLACE FUNCTION public.backfill_usage_analytics_projection(
  p_start timestamptz DEFAULT NULL,
  p_end timestamptz DEFAULT NULL,
  p_org_id text DEFAULT NULL,
  p_batch_size integer DEFAULT 5000,
  p_after_created_at timestamptz DEFAULT NULL,
  p_after_usage_id uuid DEFAULT NULL
)
RETURNS TABLE (
  inserted_count bigint,
  last_created_at timestamptz,
  last_usage_id uuid
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_batch_size IS NULL OR p_batch_size < 1 OR p_batch_size > 10000 THEN
    RAISE EXCEPTION 'usage analytics projection batch size must be between 1 and 10000';
  END IF;

  RETURN QUERY
  WITH candidates AS (
    SELECT u AS usage_row
    FROM public.usage u
    WHERE u.created_at IS NOT NULL
      AND (p_start IS NULL OR u.created_at >= p_start)
      AND (p_end IS NULL OR u.created_at <= p_end)
      AND (p_org_id IS NULL OR u.organization_id = p_org_id)
      AND (
        p_after_created_at IS NULL
        OR u.created_at > p_after_created_at
        OR (u.created_at = p_after_created_at AND (p_after_usage_id IS NULL OR u.id > p_after_usage_id))
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.usage_analytics_projection_contributions existing
        WHERE existing.usage_id = u.id
      )
    ORDER BY u.created_at ASC, u.id ASC
    LIMIT p_batch_size
  ),
  projected AS (
    SELECT contribution.*
    FROM candidates candidate
    CROSS JOIN LATERAL public.usage_analytics_projection_contribution(candidate.usage_row) contribution
  ),
  inserted AS (
    INSERT INTO public.usage_analytics_projection_contributions
    SELECT *
    FROM projected
    ON CONFLICT (usage_id) DO NOTHING
    RETURNING *
  ),
  applied AS (
    SELECT public.apply_usage_analytics_projection_delta(inserted, 1)
    FROM inserted
  ),
  bounds AS (
    SELECT
      (usage_row).created_at AS last_created_at,
      (usage_row).id AS last_usage_id
    FROM candidates
    ORDER BY (usage_row).created_at DESC, (usage_row).id DESC
    LIMIT 1
  )
  SELECT
    (SELECT count(*) FROM inserted)::bigint,
    bounds.last_created_at,
    bounds.last_usage_id
  FROM bounds
  CROSS JOIN (SELECT count(*) FROM applied) AS ensure_applied;
END;
$$;

CREATE OR REPLACE FUNCTION public.complete_usage_analytics_projection_backfill()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.usage u
    LEFT JOIN public.usage_analytics_projection_contributions contribution
      ON contribution.usage_id = u.id
    WHERE u.created_at IS NOT NULL
      AND contribution.usage_id IS NULL
    LIMIT 1
  ) THEN
    RAISE EXCEPTION 'usage analytics projection backfill is incomplete';
  END IF;

  UPDATE public.usage_analytics_projection_state
  SET historical_backfill_completed_at = COALESCE(historical_backfill_completed_at, now())
  WHERE singleton;
END;
$$;

CREATE OR REPLACE FUNCTION public.analytics_usage_rollup_v3(
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
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_bucket NOT IN ('hour', 'day', 'total') THEN
    RAISE EXCEPTION 'unsupported usage analytics bucket %', p_bucket;
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
      CASE WHEN p_bucket = 'hour' THEN 'hour'::text ELSE 'day'::text END AS truncation_unit,
      CASE WHEN p_bucket = 'hour' THEN interval '1 hour' ELSE interval '1 day' END AS bucket_width
  ),
  projection_rows AS (
    SELECT
      rollup.bucket_start AS source_bucket_start,
      rollup.category,
      rollup.campaign_id,
      rollup.user_id,
      rollup.task_label,
      rollup.model_label,
      rollup.raw_model_name,
      rollup.service_name,
      rollup.operation_name,
      rollup.company_id,
      rollup.run_id,
      rollup.metadata_research_run_id,
      rollup.api_calls,
      rollup.input_tokens,
      rollup.output_tokens,
      rollup.total_tokens,
      rollup.grounding_queries,
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
  edge_candidates AS (
    SELECT
      date_trunc(scope.truncation_unit, contribution.occurred_at AT TIME ZONE 'UTC') AT TIME ZONE 'UTC' AS source_bucket_start,
      scope.bucket_width,
      contribution.category,
      contribution.campaign_id,
      contribution.user_id,
      contribution.task_label,
      contribution.model_label,
      contribution.raw_model_name,
      contribution.service_name,
      contribution.operation_name,
      contribution.company_id,
      contribution.run_id,
      contribution.metadata_research_run_id,
      contribution.api_calls,
      contribution.input_tokens,
      contribution.output_tokens,
      contribution.total_tokens,
      contribution.grounding_queries,
      contribution.units,
      contribution.emails_found,
      contribution.people_found,
      contribution.companies_found,
      contribution.phones_found,
      contribution.original_cost,
      contribution.sellton_cost
    FROM public.usage_analytics_projection_contributions contribution
    CROSS JOIN scope
    WHERE contribution.organization_id = p_org_id
      AND contribution.occurred_at >= p_start
      AND contribution.occurred_at <= p_end
  ),
  edge_rows AS (
    SELECT
      edge.source_bucket_start,
      edge.category,
      edge.campaign_id,
      edge.user_id,
      edge.task_label,
      edge.model_label,
      edge.raw_model_name,
      edge.service_name,
      edge.operation_name,
      edge.company_id,
      edge.run_id,
      edge.metadata_research_run_id,
      edge.api_calls,
      edge.input_tokens,
      edge.output_tokens,
      edge.total_tokens,
      edge.grounding_queries,
      edge.units,
      edge.emails_found,
      edge.people_found,
      edge.companies_found,
      edge.phones_found,
      edge.original_cost,
      edge.sellton_cost
    FROM edge_candidates edge
    WHERE NOT (
      edge.source_bucket_start >= p_start
      AND edge.source_bucket_start + edge.bucket_width <= p_end
    )
  ),
  base_rows AS (
    SELECT * FROM projection_rows
    UNION ALL
    SELECT * FROM edge_rows
  ),
  scoped AS (
    SELECT
      CASE
        WHEN p_bucket = 'total' THEN date_trunc('day', p_start AT TIME ZONE 'UTC') AT TIME ZONE 'UTC'
        ELSE base_rows.source_bucket_start
      END AS grouped_bucket_start,
      base_rows.category AS grouped_category,
      base_rows.campaign_id AS grouped_campaign_id,
      base_rows.user_id AS grouped_user_id,
      base_rows.task_label AS grouped_task_label,
      base_rows.model_label AS grouped_model_label,
      base_rows.api_calls,
      base_rows.input_tokens,
      base_rows.output_tokens,
      base_rows.total_tokens,
      base_rows.grounding_queries,
      base_rows.units,
      base_rows.emails_found,
      base_rows.people_found,
      base_rows.companies_found,
      base_rows.phones_found,
      base_rows.original_cost,
      base_rows.sellton_cost
    FROM base_rows
    WHERE (NULLIF(p_category, '') IS NULL OR base_rows.category = p_category)
      AND (NULLIF(p_campaign_id, '') IS NULL OR p_campaign_id = 'all' OR base_rows.campaign_id = p_campaign_id)
      AND (NULLIF(p_model_name, '') IS NULL OR p_model_name = 'all' OR base_rows.raw_model_name = p_model_name)
      AND (NULLIF(p_user_id, '') IS NULL OR base_rows.user_id = p_user_id)
      AND (NULLIF(p_service_name, '') IS NULL OR base_rows.service_name = p_service_name)
      AND (NULLIF(p_operation, '') IS NULL OR base_rows.operation_name = p_operation)
      AND (NULLIF(p_company_id, '') IS NULL OR base_rows.company_id = p_company_id)
      AND (
        NULLIF(p_research_run_id, '') IS NULL
        OR base_rows.run_id = p_research_run_id
        OR base_rows.metadata_research_run_id = p_research_run_id
      )
  )
  SELECT
    grouped_bucket_start,
    grouped_category,
    NULLIF(grouped_campaign_id, ''),
    NULLIF(grouped_user_id, ''),
    grouped_task_label,
    NULLIF(grouped_model_label, ''),
    SUM(scoped.api_calls)::bigint,
    SUM(scoped.input_tokens)::bigint,
    SUM(scoped.output_tokens)::bigint,
    SUM(scoped.total_tokens)::bigint,
    SUM(scoped.grounding_queries)::bigint,
    SUM(scoped.units),
    SUM(scoped.emails_found),
    SUM(scoped.people_found),
    SUM(scoped.companies_found),
    SUM(scoped.phones_found),
    ROUND(SUM(scoped.original_cost), 6),
    ROUND(SUM(scoped.sellton_cost), 6)
  FROM scoped
  GROUP BY
    grouped_bucket_start,
    grouped_category,
    grouped_campaign_id,
    grouped_user_id,
    grouped_task_label,
    grouped_model_label
  ORDER BY
    grouped_bucket_start ASC,
    SUM(scoped.sellton_cost) DESC,
    grouped_category,
    grouped_task_label,
    grouped_model_label;
END;
$$;

COMMENT ON TABLE public.usage_analytics_projection_rollups IS
  'Hourly and daily Usage Analytics projection. Maintained by public.usage triggers; read by analytics_usage_rollup_v3().';

COMMENT ON TABLE public.usage_analytics_projection_contributions IS
  'One normalized analytics contribution per public.usage row. Enables idempotent backfill and exact update/delete deltas.';

COMMENT ON FUNCTION public.analytics_usage_rollup_v3(text, timestamptz, timestamptz, text, text, text, text, text, text, text, text, text) IS
  'Projection-backed Usage Analytics rollup. Preserves analytics_usage_rollup_v2 response fields and requires completed historical backfill.';

REVOKE ALL ON FUNCTION public.usage_analytics_projection_contribution(public.usage) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.apply_usage_analytics_projection_delta(public.usage_analytics_projection_contributions, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.sync_usage_analytics_projection() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.backfill_usage_analytics_projection(timestamptz, timestamptz, text, integer, timestamptz, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.complete_usage_analytics_projection_backfill() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.analytics_usage_rollup_v3(text, timestamptz, timestamptz, text, text, text, text, text, text, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.analytics_usage_rollup_v3(text, timestamptz, timestamptz, text, text, text, text, text, text, text, text, text) TO service_role;
