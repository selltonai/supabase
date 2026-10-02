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
--   tokens   with any other service_name (open-ended: sales brief, retell) -> 'research'
--   b2b_data (every other provider)                                       -> 'company_data'
--   A company-data row whose cost is 0 (original and Sellton) is hidden, calls and counts included: those are $0
--   infrastructure rows (D10). A projection row is hidden only when its whole aggregate costs 0.
-- Costs are summed exactly as v3 does (ROUND(SUM(...), 6)), so the four categories add up to v3's total.
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
SET search_path = public
AS $$
  SELECT CASE
    WHEN p_category = 'phones' THEN 'phone_numbers'
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
  -- Partial buckets at the window's edges come from the per-row contributions (as v3).
  edge_rows AS (
    SELECT
      edge.source_bucket_start,
      edge.category,
      edge.service_name,
      edge.campaign_id,
      edge.user_id,
      edge.api_calls,
      edge.input_tokens,
      edge.output_tokens,
      edge.total_tokens,
      edge.units,
      edge.emails_found,
      edge.people_found,
      edge.companies_found,
      edge.phones_found,
      edge.original_cost,
      edge.sellton_cost
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
      -- $0 infrastructure rows (company data with no cost at all) are hidden, calls and counts included.
      AND NOT (base_rows.category = 'b2b_data' AND base_rows.sellton_cost = 0 AND base_rows.original_cost = 0)
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
  'projection exactly as analytics_usage_rollup_v3, returns no model, provider or task label, and hides $0 company-data rows.';

REVOKE ALL ON FUNCTION public.usage_display_category(text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.analytics_usage_rollup_v4(text, timestamptz, timestamptz, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.usage_display_category(text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.analytics_usage_rollup_v4(text, timestamptz, timestamptz, text, text, text) TO service_role;

-- Verify (read-only):
--   SELECT display_category, sellton_cost FROM public.analytics_usage_rollup_v4('<org_id>', now() - interval '30 days', now());
--   -- The four costs add up to v3's total for the same window:
--   SELECT ROUND(SUM(sellton_cost), 6) FROM public.analytics_usage_rollup_v3('<org_id>', now() - interval '30 days', now(), 'total');
