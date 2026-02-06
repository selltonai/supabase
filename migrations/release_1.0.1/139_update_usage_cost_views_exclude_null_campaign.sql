-- Migration: Update usage_cost_daily and usage_cost_monthly views to exclude NULL campaign_id
-- Date: 2025-02-01
-- Description: Updates the views to exclude usage records without campaign_id, ensuring that
--              "all campaigns" costs only include costs from actual campaigns, not orphaned usage.

-- Drop and recreate usage_cost_daily view to exclude NULL campaign_id
DROP VIEW IF EXISTS usage_cost_daily CASCADE;

CREATE VIEW usage_cost_daily AS
SELECT 
    organization_id,
    DATE(created_at) AS usage_date,
    -- Cost aggregations
    SUM(COALESCE(original_cost, 0)) AS total_original_cost,
    SUM(COALESCE(sellton_cost, 0)) AS total_sellton_cost,
    -- Token aggregations
    SUM(COALESCE(input_tokens, 0)) AS total_input_tokens,
    SUM(COALESCE(output_tokens, 0)) AS total_output_tokens,
    SUM(COALESCE(total_tokens, 0)) AS total_tokens,
    SUM(COALESCE(api_calls, 0)) AS total_api_calls,
    -- Provider/model breakdown
    COUNT(DISTINCT provider) AS unique_providers,
    COUNT(DISTINCT model_name) AS unique_models,
    COUNT(DISTINCT session_id) AS unique_sessions,
    COUNT(DISTINCT campaign_id) AS unique_campaigns,
    -- Metadata
    COUNT(*) AS total_records,
    MIN(created_at) AS first_usage_at,
    MAX(created_at) AS last_usage_at
FROM usage
WHERE created_at IS NOT NULL
  AND campaign_id IS NOT NULL
GROUP BY organization_id, DATE(created_at);

-- Drop and recreate usage_cost_monthly view to exclude NULL campaign_id
DROP VIEW IF EXISTS usage_cost_monthly CASCADE;

CREATE VIEW usage_cost_monthly AS
SELECT 
    organization_id,
    DATE_TRUNC('month', created_at)::DATE AS usage_month,
    -- Cost aggregations
    SUM(COALESCE(original_cost, 0)) AS total_original_cost,
    SUM(COALESCE(sellton_cost, 0)) AS total_sellton_cost,
    -- Token aggregations
    SUM(COALESCE(input_tokens, 0)) AS total_input_tokens,
    SUM(COALESCE(output_tokens, 0)) AS total_output_tokens,
    SUM(COALESCE(total_tokens, 0)) AS total_tokens,
    SUM(COALESCE(api_calls, 0)) AS total_api_calls,
    -- Provider/model breakdown
    COUNT(DISTINCT provider) AS unique_providers,
    COUNT(DISTINCT model_name) AS unique_models,
    COUNT(DISTINCT session_id) AS unique_sessions,
    COUNT(DISTINCT campaign_id) AS unique_campaigns,
    -- Metadata
    COUNT(*) AS total_records,
    MIN(created_at) AS first_usage_at,
    MAX(created_at) AS last_usage_at
FROM usage
WHERE created_at IS NOT NULL
  AND campaign_id IS NOT NULL
GROUP BY organization_id, DATE_TRUNC('month', created_at);

-- Update comments to reflect the change
COMMENT ON VIEW usage_cost_daily IS 'Daily aggregated usage costs and token spend per organization (excluding records without campaign_id)';
COMMENT ON VIEW usage_cost_monthly IS 'Monthly aggregated usage costs and token spend per organization (excluding records without campaign_id)';














