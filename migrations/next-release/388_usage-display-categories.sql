-- ============================================================
-- Migration: usage-display-categories (stage: next-release/388; renumber at promotion)
-- Date:      2026-10-02
-- Purpose:   KAN-322 FR-A12 (D10): the customer Usage page shows four kinds of work (Writing, Research, Company
--            data, Phone numbers) and never a model or provider.
--              1. usage_display_category       - the one rule that maps a projection row to its display category.
--              2. analytics_usage_rollup_v4     - the Usage page's totals per display category, no model or task label.
-- Projects:  selltonai-database/supabase (owner); reader: selltonai GET /api/analytics/usage-display (FR-A12, behind
--            NEXT_PUBLIC_REFRESH_SHELL_ENABLED). analytics_usage_rollup_v3 and its readers are unchanged.
-- Contract:  New read-only functions only. No table, column, constraint, RLS, trigger, cron or queue change.
--            Safe to drop (the refreshed page shows its error state; the flag-off page never calls it).
-- Depends:   345 (usage_analytics_projection_rollups, _contributions, _state). service_name there is
--            metadata->>'service' (345 "categorized"), so no backfill is needed.
--
-- Rules (work order Addendum C, D10). 345's category already encodes the provider:
--   phones   (the airscale phone rule)                                   -> 'phone_numbers'
--   tokens   (an LLM provider) with service_name in the Writing list      -> 'writing'
--   tokens   with any other service_name (open-ended: sales brief)        -> 'research'
--   b2b_data with service_name 'retell' (the onboarding interview: Modal writes provider 'retell', which 345 files
--            under b2b_data, with a real cost; D10 counts it as Research)  -> 'research'
--   b2b_data (every other provider)                                       -> 'company_data'
--   A company-data group with no cost at all (original and Sellton) and no tokens is hidden, calls and counts
--   included: those are $0 infrastructure rows (D10). A group is one projection key in one bucket (345's primary key:
--   category, play, user, task, model, service, operation, company, run). The partial edge buckets are grouped by the
--   same key before the rule is applied. A hidden group always sums to $0 and 0 tokens, so cost and tokens never
--   depend on the window; the calls and found counts of a $0 group may (an edge holds only the key's in-window rows).
-- Costs are summed exactly as v3 does (ROUND(SUM(...), 6)) and a hidden group has no cost and no tokens, so the
-- four categories' cost and tokens add up to v3's for the same window (Borce's acceptance check).
--
-- Performance: the same reads as v3 (projection rows by organization, granularity and bucket via the primary key;
-- edge contributions via idx_usage_analytics_projection_contributions_org_occurred), grouped into at most four
-- categories per bucket. STABLE, SECURITY DEFINER (as v3: the projection tables are revoked from anon and
-- authenticated), service_role only.
--
-- Rollback: DROP FUNCTION IF EXISTS public.analytics_usage_rollup_v4(text, timestamptz, timestamptz, text, text, text);
--           DROP FUNCTION IF EXISTS public.usage_display_category(text, text);
-- ============================================================

CREATE OR REPLACE FUNCTION public.usage_display_category(p_category text, p_service_name text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
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
      'call_pitch_service'
    ) THEN 'writing'
    WHEN p_category = 'tokens' THEN 'research'
    ELSE 'company_data'
  END;
$$;

COMMENT ON FUNCTION public.usage_display_category(text, text) IS
  'KAN-322 FR-A12 (D10): maps a usage projection category and service_name to the customer display category '
  '(writing, research, company_data, phone_numbers). The Writing list is pinned by tests/usage-display-categories-contract.sql.';

CREATE OR REPLACE FUNCTION public.analytics_usage_rollup_v4(
  p_org_id text,
  p_start timestamptz,
  p_end timestamptz,
  p_bucket text DEFAULT 'total',
  p_campaign_id text DEFAULT NULL,
  p_user_id text DEFAULT NULL
)
RETURNS TABLE (
  bucket_start timestamptz,
  display_category text,
  api_calls bigint,
  input_tokens bigint,
  output_tokens bigint,
  total_tokens bigint,
  units numeric,
  emails_found numeric,
  people_found numeric,
  companies_found numeric,
  phones_found numeric,
  sellton_cost numeric
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_bucket IS NULL OR p_bucket NOT IN ('hour', 'day', 'total') THEN
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
$$;

COMMENT ON FUNCTION public.analytics_usage_rollup_v4(text, timestamptz, timestamptz, text, text, text) IS
  'KAN-322 FR-A12 (D10): the customer Usage page totals per display category (usage_display_category). Reads the 345 '
  'projection exactly as analytics_usage_rollup_v3, returns no model, provider or task label, and hides company-data groups '
  'with no cost and no tokens.';

REVOKE ALL ON FUNCTION public.usage_display_category(text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.analytics_usage_rollup_v4(text, timestamptz, timestamptz, text, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.usage_display_category(text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.analytics_usage_rollup_v4(text, timestamptz, timestamptz, text, text, text) TO service_role;

-- Verify (read-only):
--   SELECT display_category, sellton_cost, total_tokens FROM public.analytics_usage_rollup_v4('<org_id>', now() - interval '30 days', now());
--   -- The four costs (and tokens) add up to v3's for the same window:
--   SELECT ROUND(SUM(sellton_cost), 6), SUM(total_tokens) FROM public.analytics_usage_rollup_v3('<org_id>', now() - interval '30 days', now(), 'total');
--   -- Only service_role may call it (false, false, true):
--   SELECT has_function_privilege('anon', 'public.analytics_usage_rollup_v4(text,timestamptz,timestamptz,text,text,text)', 'EXECUTE'),
--          has_function_privilege('authenticated', 'public.analytics_usage_rollup_v4(text,timestamptz,timestamptz,text,text,text)', 'EXECUTE'),
--          has_function_privilege('service_role', 'public.analytics_usage_rollup_v4(text,timestamptz,timestamptz,text,text,text)', 'EXECUTE');
