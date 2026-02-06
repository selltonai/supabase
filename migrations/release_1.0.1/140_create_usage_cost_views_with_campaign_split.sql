-- Migration: Create views for usage costs split by campaign vs non-campaign
-- Date: 2025-02-04
-- Description: Creates views that separate campaign-related costs from non-campaign-related costs
--              This allows clear visibility into both types of costs in the dashboard

-- Drop existing views if they exist (for idempotency)
DROP VIEW IF EXISTS usage_cost_daily_with_split CASCADE;
DROP VIEW IF EXISTS usage_cost_monthly_with_split CASCADE;

-- Create daily cost view with campaign/non-campaign split
-- This view includes both campaign-related (campaign_id IS NOT NULL) and non-campaign-related (campaign_id IS NULL) costs
CREATE VIEW usage_cost_daily_with_split AS
SELECT 
    organization_id,
    DATE(created_at) AS usage_date,
    CASE 
        WHEN campaign_id IS NOT NULL THEN 'campaign'
        ELSE 'non_campaign'
    END AS cost_type,
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
GROUP BY organization_id, DATE(created_at), CASE WHEN campaign_id IS NOT NULL THEN 'campaign' ELSE 'non_campaign' END;

-- Create monthly cost view with campaign/non-campaign split
CREATE VIEW usage_cost_monthly_with_split AS
SELECT 
    organization_id,
    DATE_TRUNC('month', created_at)::DATE AS usage_month,
    CASE 
        WHEN campaign_id IS NOT NULL THEN 'campaign'
        ELSE 'non_campaign'
    END AS cost_type,
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
GROUP BY organization_id, DATE_TRUNC('month', created_at), CASE WHEN campaign_id IS NOT NULL THEN 'campaign' ELSE 'non_campaign' END;

-- Add comments for documentation
COMMENT ON VIEW usage_cost_daily_with_split IS 'Daily aggregated usage costs split by campaign-related vs non-campaign-related costs';
COMMENT ON VIEW usage_cost_monthly_with_split IS 'Monthly aggregated usage costs split by campaign-related vs non-campaign-related costs';














