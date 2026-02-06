-- Migration: Create views for daily and monthly usage costs
-- Date: 2025-01-31
-- Description: Creates materialized views for fast loading of daily and monthly token spend/costs

-- Drop existing views if they exist (for idempotency)
DROP VIEW IF EXISTS usage_cost_daily CASCADE;
DROP VIEW IF EXISTS usage_cost_monthly CASCADE;

-- Create daily cost view
-- Groups usage by organization and date, aggregating costs and tokens
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
GROUP BY organization_id, DATE(created_at);

-- Create monthly cost view
-- Groups usage by organization and month, aggregating costs and tokens
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
GROUP BY organization_id, DATE_TRUNC('month', created_at);

-- Create indexes on the underlying table for better query performance
-- These indexes help optimize queries against the views

-- Index for daily queries (organization_id + created_at date)
-- Note: PostgreSQL doesn't support functional indexes directly on DATE() in all cases,
-- but we can create an index on created_at which will help with date filtering
CREATE INDEX IF NOT EXISTS idx_usage_org_created_desc ON usage(organization_id, created_at DESC);

-- Index for cost-based queries
CREATE INDEX IF NOT EXISTS idx_usage_org_costs ON usage(organization_id, sellton_cost, original_cost) WHERE sellton_cost > 0 OR original_cost > 0;

-- Add comments for documentation
COMMENT ON VIEW usage_cost_daily IS 'Daily aggregated usage costs and token spend per organization';
COMMENT ON VIEW usage_cost_monthly IS 'Monthly aggregated usage costs and token spend per organization';

