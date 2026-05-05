ALTER TABLE IF EXISTS public.usage
  ADD COLUMN IF NOT EXISTS user_id text;

CREATE INDEX IF NOT EXISTS idx_usage_user_id
  ON public.usage (user_id);

CREATE INDEX IF NOT EXISTS idx_usage_org_user_created
  ON public.usage (organization_id, user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public.action_label_map (
  provider text NOT NULL DEFAULT '',
  service_name text NOT NULL DEFAULT '',
  model_name_pattern text NOT NULL DEFAULT '',
  requires_grounding boolean NOT NULL DEFAULT false,
  task_key text NOT NULL,
  display_label text NOT NULL,
  priority integer NOT NULL DEFAULT 100,
  PRIMARY KEY (provider, service_name, model_name_pattern, requires_grounding, task_key)
);

INSERT INTO public.action_label_map (
  provider,
  service_name,
  model_name_pattern,
  requires_grounding,
  task_key,
  display_label,
  priority
)
VALUES
  ('openai', 'email_generation_service', '%', false, 'email_copywriting', 'Email copywriting', 10),
  ('anthropic', 'email_generation_service', '%', false, 'email_copywriting', 'Email copywriting', 10),
  ('togetherai', 'email_generation_service', '%', false, 'email_copywriting', 'Email copywriting', 10),
  ('openai', 'email_reply_processor_service', '%', false, 'email_reply_handling', 'Email reply handling', 10),
  ('anthropic', 'email_reply_processor_service', '%', false, 'email_reply_handling', 'Email reply handling', 10),
  ('togetherai', 'email_reply_processor_service', '%', false, 'email_reply_handling', 'Email reply handling', 10),
  ('gemini', '', 'gemini-%', true, 'web_search', 'Web search (grounding)', 5),
  ('gemini', '', 'gemini-%', false, 'llm_generation', 'LLM generation', 20),
  ('openai', '', 'gpt-%', false, 'llm_generation', 'LLM generation', 20),
  ('openai', '', 'o%-mini', false, 'llm_generation', 'LLM generation', 20),
  ('openai', '', 'o3', false, 'llm_generation', 'LLM generation', 20),
  ('togetherai', '', 'deepseek%', false, 'llm_generation', 'LLM generation', 20),
  ('perplexity', '', 'sonar%', false, 'web_research', 'Web research', 20),
  ('exa', '', 'exa-%', false, 'web_research', 'Web research', 10),
  ('hunter', '', 'hunter-%', false, 'email_finder', 'Email finder', 10),
  ('icypeas', '', 'icypeas-%', false, 'email_finder', 'Email finder', 10),
  ('apollo', '', 'apollo-%', false, 'email_finder', 'Email finder', 10),
  ('airscale', '', 'airscale-email%', false, 'email_finder', 'Email finder', 10),
  ('airscale', '', 'airscale-phone%', false, 'phone_discovery', 'Phone discovery', 10),
  ('ai_ark', '', 'ai-ark-%', false, 'people_search', 'People search', 10),
  ('b2b_enrichment', '', 'b2b-email_verifier%', false, 'email_verifier', 'Email verifier', 10),
  ('b2b_enrichment', '', 'b2b-email_finder%', false, 'email_finder', 'Email finder', 10),
  ('b2b_enrichment', '', 'b2b-people_search%', false, 'people_search', 'People search', 10),
  ('b2b_enrichment', '', 'b2b-company_profile%', false, 'company_search', 'Company search', 10),
  ('b2b_enrichment', '', 'b2b-similar_companies%', false, 'company_search', 'Company search', 10),
  ('b2b_enrichment', '', 'b2b-%', false, 'contact_enrichment', 'Contact enrichment', 50)
ON CONFLICT (provider, service_name, model_name_pattern, requires_grounding, task_key)
DO UPDATE SET
  display_label = EXCLUDED.display_label,
  priority = EXCLUDED.priority;

CREATE TABLE IF NOT EXISTS public.billing_week_snapshot (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL,
  week_start date NOT NULL,
  week_end date NOT NULL,
  line_items jsonb NOT NULL DEFAULT '[]'::jsonb,
  total_sellton_cost numeric NOT NULL DEFAULT 0,
  generated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, week_start)
);

CREATE INDEX IF NOT EXISTS idx_billing_week_snapshot_org_week
  ON public.billing_week_snapshot (organization_id, week_start DESC);

CREATE OR REPLACE FUNCTION public.analytics_usage_rollup(
  p_org_id text,
  p_start timestamptz,
  p_end timestamptz,
  p_bucket text,
  p_user_id text DEFAULT NULL
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
  grounding_queries bigint,
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
      u.api_calls,
      u.input_tokens,
      u.output_tokens,
      COALESCE((u.metadata ->> 'grounding_queries')::bigint, 0) AS grounding_queries,
      COALESCE(u.original_cost, 0)::numeric AS original_cost,
      COALESCE(u.sellton_cost, 0)::numeric AS sellton_cost,
      u.metadata
    FROM public.usage u
    WHERE u.organization_id = p_org_id
      AND u.created_at >= p_start
      AND u.created_at <= p_end
      AND (p_user_id IS NULL OR u.user_id = p_user_id)
  ),
  categorized AS (
    SELECT
      b.*,
      CASE
        WHEN b.provider = 'airscale'
          AND (
            COALESCE(b.metadata ->> 'action', '') = 'phone_finder'
            OR COALESCE(b.model_name, '') LIKE 'airscale-phone%'
          ) THEN 'phones'
        WHEN b.provider IN ('openai', 'anthropic', 'deepseek', 'togetherai', 'perplexity', 'gemini', 'mistral') THEN 'tokens'
        ELSE 'b2b_data'
      END AS category
    FROM base_usage b
  ),
  labeled AS (
    SELECT
      c.bucket_start,
      c.category,
      c.campaign_id,
      c.user_id,
      COALESCE(
        map.display_label,
        CASE
          WHEN c.provider = 'gemini' AND c.grounding_queries > 0 THEN 'Web search (grounding)'
          WHEN c.category = 'phones' THEN 'Phone discovery'
          WHEN c.provider = 'hunter' THEN 'Email finder'
          WHEN c.provider = 'icypeas' THEN 'Email finder'
          WHEN c.provider = 'apollo' THEN 'Email finder'
          WHEN c.provider = 'exa' THEN 'Web research'
          WHEN c.provider = 'ai_ark' THEN 'People search'
          WHEN c.provider = 'b2b_enrichment' AND COALESCE(c.model_name, '') LIKE 'b2b-email_verifier%' THEN 'Email verifier'
          WHEN c.provider = 'b2b_enrichment' AND COALESCE(c.model_name, '') LIKE 'b2b-email_finder%' THEN 'Email finder'
          WHEN c.provider = 'b2b_enrichment' AND COALESCE(c.model_name, '') LIKE 'b2b-people_search%' THEN 'People search'
          WHEN c.provider = 'b2b_enrichment' AND COALESCE(c.model_name, '') LIKE 'b2b-company_profile%' THEN 'Company search'
          WHEN c.provider = 'b2b_enrichment' THEN 'Contact enrichment'
          ELSE 'LLM generation'
        END
      ) AS task_label,
      CASE
        WHEN c.category = 'tokens' THEN c.model_name
        ELSE NULL
      END AS model_label,
      c.api_calls,
      c.input_tokens,
      c.output_tokens,
      c.grounding_queries,
      c.original_cost,
      c.sellton_cost
    FROM categorized c
    LEFT JOIN LATERAL (
      SELECT m.display_label
      FROM public.action_label_map m
      WHERE (m.provider = '' OR m.provider = c.provider)
        AND (m.service_name = '' OR m.service_name = COALESCE(c.metadata ->> 'service', ''))
        AND (m.model_name_pattern = '' OR COALESCE(c.model_name, '') LIKE m.model_name_pattern)
        AND (NOT m.requires_grounding OR c.grounding_queries > 0)
      ORDER BY m.priority ASC
      LIMIT 1
    ) map ON TRUE
  )
  SELECT
    l.bucket_start,
    l.category,
    l.campaign_id,
    l.user_id,
    l.task_label,
    l.model_label,
    SUM(l.api_calls)::bigint AS api_calls,
    SUM(l.input_tokens)::bigint AS input_tokens,
    SUM(l.output_tokens)::bigint AS output_tokens,
    SUM(l.grounding_queries)::bigint AS grounding_queries,
    ROUND(SUM(l.original_cost), 6) AS original_cost,
    ROUND(SUM(l.sellton_cost), 6) AS sellton_cost
  FROM labeled l
  GROUP BY
    l.bucket_start,
    l.category,
    l.campaign_id,
    l.user_id,
    l.task_label,
    l.model_label
  ORDER BY l.bucket_start DESC, l.category, l.task_label, l.model_label;
$$;

COMMENT ON FUNCTION public.analytics_usage_rollup(text, timestamptz, timestamptz, text, text)
  IS 'Unified usage rollup for Tokens / B2B Data / Phones, including campaign_id IS NULL rows and optional user filtering.';

COMMENT ON VIEW public.usage_cost_daily
  IS 'DEPRECATED: campaign-only daily aggregated usage costs. Excludes campaign_id IS NULL rows; prefer analytics_usage_rollup().';

GRANT EXECUTE ON FUNCTION public.analytics_usage_rollup(text, timestamptz, timestamptz, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.analytics_usage_rollup(text, timestamptz, timestamptz, text, text) TO service_role;

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.action_label_map TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.action_label_map TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.billing_week_snapshot TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.billing_week_snapshot TO service_role;
