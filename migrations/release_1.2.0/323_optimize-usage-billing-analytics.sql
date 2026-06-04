-- Usage and billing analytics performance hotfix.
--
-- What changed:
--   - Adds composite indexes for the Usage page filters that scan public.usage.
--   - Adds UTC-date expression indexes for daily usage and billing views.
--   - Recreates analytics_usage_daily and billing usage views with UTC date buckets
--     so they match the existing idx_usage_created_at_date convention.
--
-- Projects depending on this:
--   - selltonai reads analytics_usage_daily and /api/analytics/usage-rollup.
--   - selltonai-modal reads billing_usage_uninvoiced_by_service_user and
--     billing_usage_daily_by_service_user from billing endpoints.
--
-- Application code update:
--   - No response shape changes. Deploy with the selltonai usage-page
--     fetch reduction and rollup metadata parsing fix.

CREATE INDEX IF NOT EXISTS idx_usage_analytics_org_model_created
  ON public.usage (organization_id, model_name, created_at DESC)
  WHERE model_name IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_usage_analytics_org_campaign_created
  ON public.usage (organization_id, campaign_id, created_at DESC)
  WHERE campaign_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_usage_analytics_org_user_created
  ON public.usage (organization_id, user_id, created_at DESC)
  WHERE user_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_usage_analytics_org_run_created
  ON public.usage (organization_id, run_id, created_at DESC)
  WHERE run_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_usage_analytics_org_utc_date_provider_model
  ON public.usage (
    organization_id,
    (DATE(created_at AT TIME ZONE 'UTC')),
    provider,
    model_name,
    campaign_id,
    user_id
  )
  WHERE created_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_usage_billing_org_utc_date_service_user
  ON public.usage (
    organization_id,
    (DATE(created_at AT TIME ZONE 'UTC')),
    (metadata->>'service'),
    user_id
  )
  WHERE created_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_usage_billing_uninvoiced_org_utc_date_service_user
  ON public.usage (
    organization_id,
    (DATE(created_at AT TIME ZONE 'UTC')),
    (metadata->>'service'),
    user_id
  )
  WHERE created_at IS NOT NULL
    AND invoice_id IS NULL;

CREATE OR REPLACE VIEW public.analytics_usage_daily AS
SELECT
  organization_id,
  DATE(created_at AT TIME ZONE 'UTC') AS usage_date,
  provider,
  model_name,
  campaign_id,
  user_id,
  SUM(COALESCE(input_tokens, 0)) AS total_input_tokens,
  SUM(COALESCE(output_tokens, 0)) AS total_output_tokens,
  SUM(COALESCE(total_tokens, 0)) AS total_tokens,
  SUM(COALESCE(api_calls, 0)) AS total_api_calls,
  SUM(COALESCE(original_cost, 0)) AS total_original_cost,
  SUM(COALESCE(sellton_cost, 0)) AS total_sellton_cost,
  COUNT(DISTINCT session_id) AS unique_sessions,
  COUNT(*) AS total_records,
  MIN(created_at) AS first_usage_at,
  MAX(created_at) AS last_usage_at
FROM public.usage
WHERE created_at IS NOT NULL
GROUP BY
  organization_id,
  DATE(created_at AT TIME ZONE 'UTC'),
  provider,
  model_name,
  campaign_id,
  user_id;

COMMENT ON VIEW public.analytics_usage_daily IS
  'Daily usage analytics grouped by org/date/provider/model/campaign/user. Uses UTC date buckets.';

CREATE OR REPLACE VIEW public.billing_usage_daily_by_service_user AS
SELECT
  organization_id,
  DATE(created_at AT TIME ZONE 'UTC') AS usage_date,
  metadata->>'service' AS service,
  user_id,
  SUM(COALESCE(total_tokens, 0)) AS total_tokens,
  SUM(COALESCE(sellton_cost, 0)) AS total_sellton_cost,
  COUNT(*) AS total_records
FROM public.usage
WHERE created_at IS NOT NULL
GROUP BY organization_id, DATE(created_at AT TIME ZONE 'UTC'), metadata->>'service', user_id;

COMMENT ON VIEW public.billing_usage_daily_by_service_user IS
  'Billing aggregation: usage grouped by org/date/service/user. Uses UTC date buckets.';

CREATE OR REPLACE VIEW public.billing_usage_uninvoiced_by_service_user AS
SELECT
  organization_id,
  DATE(created_at AT TIME ZONE 'UTC') AS usage_date,
  metadata->>'service' AS service,
  user_id,
  SUM(COALESCE(total_tokens, 0)) AS total_tokens,
  SUM(COALESCE(sellton_cost, 0)) AS total_sellton_cost,
  COUNT(*) AS total_records
FROM public.usage
WHERE created_at IS NOT NULL
  AND invoice_id IS NULL
GROUP BY organization_id, DATE(created_at AT TIME ZONE 'UTC'), metadata->>'service', user_id;

COMMENT ON VIEW public.billing_usage_uninvoiced_by_service_user IS
  'Billing aggregation: uninvoiced usage grouped by org/date/service/user. Uses UTC date buckets.';

GRANT SELECT ON TABLE public.analytics_usage_daily TO service_role;
GRANT SELECT ON TABLE public.billing_usage_daily_by_service_user TO service_role;
GRANT SELECT ON TABLE public.billing_usage_uninvoiced_by_service_user TO service_role;
