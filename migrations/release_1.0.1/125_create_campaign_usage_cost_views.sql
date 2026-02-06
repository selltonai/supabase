-- Migration: Create views for campaign-level daily and monthly usage costs
-- Date: 2025-01-31
-- Description: Creates views for fast loading of daily and monthly token spend/costs per campaign

-- Drop existing views if they exist (for idempotency)
DROP VIEW IF EXISTS usage_cost_daily_by_campaign CASCADE;
DROP VIEW IF EXISTS usage_cost_monthly_by_campaign CASCADE;

-- Create daily cost view by campaign
-- Groups usage by organization, campaign, and date
CREATE VIEW usage_cost_daily_by_campaign AS
SELECT 
    organization_id,
    campaign_id,
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
    -- Metadata
    COUNT(*) AS total_records,
    MIN(created_at) AS first_usage_at,
    MAX(created_at) AS last_usage_at
FROM usage
WHERE created_at IS NOT NULL
  AND campaign_id IS NOT NULL
GROUP BY organization_id, campaign_id, DATE(created_at);

-- Create monthly cost view by campaign
-- Groups usage by organization, campaign, and month
CREATE VIEW usage_cost_monthly_by_campaign AS
SELECT 
    organization_id,
    campaign_id,
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
    -- Metadata
    COUNT(*) AS total_records,
    MIN(created_at) AS first_usage_at,
    MAX(created_at) AS last_usage_at
FROM usage
WHERE created_at IS NOT NULL
  AND campaign_id IS NOT NULL
GROUP BY organization_id, campaign_id, DATE_TRUNC('month', created_at);

-- Add comments for documentation
COMMENT ON VIEW usage_cost_daily_by_campaign IS 'Daily aggregated usage costs and token spend per organization and campaign';
COMMENT ON VIEW usage_cost_monthly_by_campaign IS 'Monthly aggregated usage costs and token spend per organization and campaign';

