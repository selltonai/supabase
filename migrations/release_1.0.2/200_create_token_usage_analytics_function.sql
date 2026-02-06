-- Migration: Create function for token usage analytics
-- Date: 2025-12-08
-- Description: SQL function for accurate token usage analytics with proper date handling
-- This function handles date ranges correctly regardless of timezone

-- Drop existing function if it exists
DROP FUNCTION IF EXISTS get_token_usage_summary(UUID, DATE, DATE, TEXT, UUID);

-- Create the function for daily token usage summary
CREATE OR REPLACE FUNCTION get_token_usage_summary(
    p_organization_id UUID,
    p_start_date DATE,
    p_end_date DATE,
    p_model_name TEXT DEFAULT NULL,
    p_campaign_id UUID DEFAULT NULL
)
RETURNS TABLE (
    period_start TIMESTAMP WITH TIME ZONE,
    total_input_tokens BIGINT,
    total_output_tokens BIGINT,
    total_tokens BIGINT,
    total_runs BIGINT,
    total_api_calls BIGINT,
    provider TEXT,
    model_name TEXT,
    unique_sessions BIGINT
) AS $$
BEGIN
    RETURN QUERY
    WITH date_series AS (
        -- Generate all dates in the range
        SELECT generate_series(
            p_start_date::timestamp AT TIME ZONE 'UTC',
            p_end_date::timestamp AT TIME ZONE 'UTC',
            '1 day'::interval
        )::date AS usage_date
    ),
    daily_usage AS (
        -- Aggregate usage data by date (using DATE to extract UTC date)
        SELECT 
            DATE(u.created_at AT TIME ZONE 'UTC') AS usage_date,
            SUM(COALESCE(u.input_tokens, 0))::BIGINT AS total_input_tokens,
            SUM(COALESCE(u.output_tokens, 0))::BIGINT AS total_output_tokens,
            SUM(COALESCE(u.total_tokens, 0))::BIGINT AS total_tokens,
            SUM(COALESCE(u.api_calls, 0))::BIGINT AS total_runs,
            SUM(COALESCE(u.api_calls, 0))::BIGINT AS total_api_calls,
            STRING_AGG(DISTINCT u.provider, ', ') AS provider,
            STRING_AGG(DISTINCT u.model_name, ', ') AS model_name,
            COUNT(DISTINCT u.session_id)::BIGINT AS unique_sessions
        FROM usage u
        WHERE u.organization_id = p_organization_id
          AND DATE(u.created_at AT TIME ZONE 'UTC') >= p_start_date
          AND DATE(u.created_at AT TIME ZONE 'UTC') <= p_end_date
          AND (p_model_name IS NULL OR u.model_name = p_model_name)
          AND (p_campaign_id IS NULL OR u.campaign_id = p_campaign_id)
        GROUP BY DATE(u.created_at AT TIME ZONE 'UTC')
    )
    SELECT 
        (ds.usage_date || 'T00:00:00Z')::timestamp with time zone AS period_start,
        COALESCE(du.total_input_tokens, 0)::BIGINT,
        COALESCE(du.total_output_tokens, 0)::BIGINT,
        COALESCE(du.total_tokens, 0)::BIGINT,
        COALESCE(du.total_runs, 0)::BIGINT,
        COALESCE(du.total_api_calls, 0)::BIGINT,
        COALESCE(du.provider, '')::TEXT,
        COALESCE(du.model_name, '')::TEXT,
        COALESCE(du.unique_sessions, 0)::BIGINT
    FROM date_series ds
    LEFT JOIN daily_usage du ON ds.usage_date = du.usage_date
    ORDER BY ds.usage_date;
END;
$$ LANGUAGE plpgsql STABLE;

-- Create function for token usage stats (totals)
DROP FUNCTION IF EXISTS get_token_usage_stats(UUID, DATE, DATE, TEXT, UUID);

CREATE OR REPLACE FUNCTION get_token_usage_stats(
    p_organization_id UUID,
    p_start_date DATE,
    p_end_date DATE,
    p_model_name TEXT DEFAULT NULL,
    p_campaign_id UUID DEFAULT NULL
)
RETURNS TABLE (
    total_input_tokens BIGINT,
    total_output_tokens BIGINT,
    total_tokens BIGINT,
    total_processing_time NUMERIC,
    total_runs BIGINT,
    total_api_calls BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        COALESCE(SUM(u.input_tokens), 0)::BIGINT AS total_input_tokens,
        COALESCE(SUM(u.output_tokens), 0)::BIGINT AS total_output_tokens,
        COALESCE(SUM(u.total_tokens), 0)::BIGINT AS total_tokens,
        0::NUMERIC AS total_processing_time,
        COALESCE(SUM(u.api_calls), 0)::BIGINT AS total_runs,
        COALESCE(SUM(u.api_calls), 0)::BIGINT AS total_api_calls
    FROM usage u
    WHERE u.organization_id = p_organization_id
      AND DATE(u.created_at AT TIME ZONE 'UTC') >= p_start_date
      AND DATE(u.created_at AT TIME ZONE 'UTC') <= p_end_date
      AND (p_model_name IS NULL OR u.model_name = p_model_name)
      AND (p_campaign_id IS NULL OR u.campaign_id = p_campaign_id);
END;
$$ LANGUAGE plpgsql STABLE;

-- Add comments
COMMENT ON FUNCTION get_token_usage_summary IS 'Returns daily token usage summary for an organization with proper UTC date handling';
COMMENT ON FUNCTION get_token_usage_stats IS 'Returns aggregated token usage stats for an organization with proper UTC date handling';

-- Create an index to optimize the date extraction query
CREATE INDEX IF NOT EXISTS idx_usage_created_at_date ON usage (organization_id, (DATE(created_at AT TIME ZONE 'UTC')));




