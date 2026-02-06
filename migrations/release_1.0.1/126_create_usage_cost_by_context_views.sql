-- Migration: Create views for usage costs grouped by usage_context
-- Date: 2025-01-31
-- Description: Creates views for fast loading of token spend/costs grouped by usage context
--              This allows tracking costs per operation type (e.g., email generation, company research)

-- Drop existing views if they exist (for idempotency)
DROP VIEW IF EXISTS usage_cost_by_context CASCADE;
DROP VIEW IF EXISTS usage_cost_daily_by_context CASCADE;
DROP VIEW IF EXISTS usage_cost_monthly_by_context CASCADE;

-- Create view for total usage by context (all time)
CREATE VIEW usage_cost_by_context AS
SELECT 
    organization_id,
    usage_context,
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
    COUNT(DISTINCT campaign_id) AS unique_campaigns,
    COUNT(DISTINCT session_id) AS unique_sessions,
    -- Metadata
    COUNT(*) AS total_records,
    MIN(created_at) AS first_usage_at,
    MAX(created_at) AS last_usage_at
FROM usage
WHERE usage_context IS NOT NULL
GROUP BY organization_id, usage_context;

-- Create daily cost view by context
CREATE VIEW usage_cost_daily_by_context AS
SELECT 
    organization_id,
    usage_context,
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
    COUNT(DISTINCT campaign_id) AS unique_campaigns,
    COUNT(DISTINCT session_id) AS unique_sessions,
    -- Metadata
    COUNT(*) AS total_records,
    MIN(created_at) AS first_usage_at,
    MAX(created_at) AS last_usage_at
FROM usage
WHERE usage_context IS NOT NULL
  AND created_at IS NOT NULL
GROUP BY organization_id, usage_context, DATE(created_at);

-- Create monthly cost view by context
CREATE VIEW usage_cost_monthly_by_context AS
SELECT 
    organization_id,
    usage_context,
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
    COUNT(DISTINCT campaign_id) AS unique_campaigns,
    COUNT(DISTINCT session_id) AS unique_sessions,
    -- Metadata
    COUNT(*) AS total_records,
    MIN(created_at) AS first_usage_at,
    MAX(created_at) AS last_usage_at
FROM usage
WHERE usage_context IS NOT NULL
  AND created_at IS NOT NULL
GROUP BY organization_id, usage_context, DATE_TRUNC('month', created_at);

-- Create index for better query performance
CREATE INDEX IF NOT EXISTS idx_usage_context ON usage(organization_id, usage_context, created_at DESC);

-- Add comments for documentation
COMMENT ON VIEW usage_cost_by_context IS 'Total aggregated usage costs and token spend per organization and usage context';
COMMENT ON VIEW usage_cost_daily_by_context IS 'Daily aggregated usage costs and token spend per organization and usage context';
COMMENT ON VIEW usage_cost_monthly_by_context IS 'Monthly aggregated usage costs and token spend per organization and usage context';

