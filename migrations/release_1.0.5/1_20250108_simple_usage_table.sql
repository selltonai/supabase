-- Simple Usage Table Migration
-- This migration creates a single 'usage' table for all API tracking
-- Handles both credit-based APIs (Exa, B2B) and token-based APIs (Agents, DeepSeek)

-- Drop existing triggers and functions if they exist
DO $$
BEGIN
    -- Drop trigger only if table exists
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'usage') THEN
        DROP TRIGGER IF EXISTS update_usage_summary_trigger ON usage;
    END IF;
END $$;

DROP FUNCTION IF EXISTS update_usage_summary();
DROP FUNCTION IF EXISTS get_usage_by_date_range(TEXT, DATE, DATE, TEXT);
DROP VIEW IF EXISTS daily_usage_stats;

-- Drop existing enums if they exist
DROP TYPE IF EXISTS api_provider CASCADE;
DROP TYPE IF EXISTS usage_context_type CASCADE;

-- Create enums for consistent provider and context values
CREATE TYPE api_provider AS ENUM (
    'b2b_enrichment',
    'exa', 
    'perplexity',
    'openai',
    'deepseek',
    'togetherai',
    'mistral'
);

CREATE TYPE usage_context_type AS ENUM (
    'agent_run',
    'direct_api',
    'batch_processing'
);

-- Create usage table for all API/Agent tracking
CREATE TABLE IF NOT EXISTS usage (
    id BIGSERIAL PRIMARY KEY,
    organization_id TEXT NOT NULL,
    session_id TEXT NOT NULL,
    provider TEXT NOT NULL,  -- 'openai', 'deepseek', 'exa', 'b2b_enrichment', etc.
    model_name TEXT,         -- Actual model name from API response
    
    -- Usage tracking (flexible for both credits and tokens)
    api_calls INTEGER DEFAULT 0,        -- Number of API calls (for credit-based APIs)
    input_tokens INTEGER DEFAULT 0,     -- Input tokens (for token-based APIs)
    output_tokens INTEGER DEFAULT 0,    -- Output tokens (for token-based APIs)
    total_tokens INTEGER DEFAULT 0,     -- Total tokens (calculated or provided)
    
    -- Metadata and linking
    usage_context TEXT DEFAULT 'direct_api',  -- Usage context: 'agent_run', 'direct_api', 'batch_processing'
    run_id TEXT,                        -- Optional: Link to agent run or operation
    agent_id TEXT,                      -- Optional: Agent identifier
    description TEXT,                   -- Optional: Description of operation
    
    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    tracking_start TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    tracking_end TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- Raw data storage
    metadata JSONB DEFAULT '{}'::jsonb
);

-- Add usage_context column if it doesn't exist (for existing tables)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'usage') THEN
        ALTER TABLE usage ADD COLUMN IF NOT EXISTS usage_context TEXT DEFAULT 'direct_api';
    END IF;
END $$;

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_usage_org_session ON usage(organization_id, session_id);
CREATE INDEX IF NOT EXISTS idx_usage_provider ON usage(provider);
CREATE INDEX IF NOT EXISTS idx_usage_created ON usage(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_usage_org_provider ON usage(organization_id, provider);

-- Create usage_summary table for aggregated data
CREATE TABLE IF NOT EXISTS usage_summary (
    id BIGSERIAL PRIMARY KEY,
    organization_id TEXT NOT NULL,
    provider TEXT NOT NULL,
    model_name TEXT,
    date DATE NOT NULL,              -- Daily summaries
    
    -- Aggregated metrics
    total_api_calls INTEGER DEFAULT 0,
    total_input_tokens INTEGER DEFAULT 0,
    total_output_tokens INTEGER DEFAULT 0,
    total_tokens INTEGER DEFAULT 0,
    unique_sessions INTEGER DEFAULT 0,
    
    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- Unique constraint for daily summaries
    UNIQUE(organization_id, provider, model_name, date)
);

-- Create indexes for usage_summary
CREATE INDEX IF NOT EXISTS idx_usage_summary_org_date ON usage_summary(organization_id, date DESC);
CREATE INDEX IF NOT EXISTS idx_usage_summary_provider ON usage_summary(provider);

-- Create function to update usage summary
CREATE OR REPLACE FUNCTION update_usage_summary()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO usage_summary (
        organization_id,
        provider,
        model_name,
        date,
        total_api_calls,
        total_input_tokens,
        total_output_tokens,
        total_tokens,
        unique_sessions
    ) VALUES (
        NEW.organization_id,
        NEW.provider,
        NEW.model_name,
        DATE(NEW.created_at),
        NEW.api_calls,
        NEW.input_tokens,
        NEW.output_tokens,
        NEW.total_tokens,
        1  -- This will be recalculated in the conflict resolution
    )
    ON CONFLICT (organization_id, provider, model_name, date)
    DO UPDATE SET
        total_api_calls = usage_summary.total_api_calls + NEW.api_calls,
        total_input_tokens = usage_summary.total_input_tokens + NEW.input_tokens,
        total_output_tokens = usage_summary.total_output_tokens + NEW.output_tokens,
        total_tokens = usage_summary.total_tokens + NEW.total_tokens,
        unique_sessions = (
            SELECT COUNT(DISTINCT session_id) 
            FROM usage 
            WHERE organization_id = NEW.organization_id 
            AND provider = NEW.provider 
            AND COALESCE(model_name, '') = COALESCE(NEW.model_name, '')
            AND DATE(created_at) = DATE(NEW.created_at)
        ),
        updated_at = NOW();
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to automatically update summary
CREATE TRIGGER update_usage_summary_trigger
    AFTER INSERT ON usage
    FOR EACH ROW
    EXECUTE FUNCTION update_usage_summary();

-- Create function to get usage by date range
CREATE OR REPLACE FUNCTION get_usage_by_date_range(
    p_organization_id TEXT,
    p_start_date DATE,
    p_end_date DATE,
    p_provider TEXT DEFAULT NULL
)
RETURNS TABLE (
    provider TEXT,
    model_name TEXT,
    total_api_calls BIGINT,
    total_input_tokens BIGINT,
    total_output_tokens BIGINT,
    total_tokens BIGINT,
    unique_sessions BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        u.provider,
        u.model_name,
        SUM(u.api_calls)::BIGINT as total_api_calls,
        SUM(u.input_tokens)::BIGINT as total_input_tokens,
        SUM(u.output_tokens)::BIGINT as total_output_tokens,
        SUM(u.total_tokens)::BIGINT as total_tokens,
        COUNT(DISTINCT u.session_id)::BIGINT as unique_sessions
    FROM usage u
    WHERE u.organization_id = p_organization_id
        AND DATE(u.created_at) >= p_start_date
        AND DATE(u.created_at) <= p_end_date
        AND (p_provider IS NULL OR u.provider = p_provider)
    GROUP BY u.provider, u.model_name
    ORDER BY u.provider, u.model_name;
END;
$$ LANGUAGE plpgsql;

-- Create view for daily usage stats
CREATE OR REPLACE VIEW daily_usage_stats AS
SELECT 
    organization_id,
    DATE(created_at) as usage_date,
    provider,
    model_name,
    SUM(api_calls) as daily_api_calls,
    SUM(input_tokens) as daily_input_tokens,
    SUM(output_tokens) as daily_output_tokens,
    SUM(total_tokens) as daily_total_tokens,
    COUNT(DISTINCT session_id) as unique_sessions,
    COUNT(*) as total_operations
FROM usage
GROUP BY organization_id, DATE(created_at), provider, model_name;

-- Add RLS policies
ALTER TABLE usage ENABLE ROW LEVEL SECURITY;
ALTER TABLE usage_summary ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Allow all operations on usage" ON usage;
DROP POLICY IF EXISTS "Allow all operations on usage_summary" ON usage_summary;

-- Simple policies that allow all operations (adjust based on your auth setup)
CREATE POLICY "Allow all operations on usage" ON usage FOR ALL USING (true);
CREATE POLICY "Allow all operations on usage_summary" ON usage_summary FOR ALL USING (true);

-- Grant permissions
GRANT ALL ON usage TO service_role;
GRANT ALL ON usage_summary TO service_role;
GRANT ALL ON SEQUENCE usage_id_seq TO service_role;
GRANT ALL ON SEQUENCE usage_summary_id_seq TO service_role;
GRANT SELECT ON daily_usage_stats TO service_role;

-- Add comments for documentation
COMMENT ON TABLE usage IS 'Universal usage tracking for all APIs and agents - handles both credit-based and token-based systems';
COMMENT ON COLUMN usage.api_calls IS 'Number of API calls made (primarily for credit-based APIs like Exa, B2B)';
COMMENT ON COLUMN usage.input_tokens IS 'Input tokens used (for token-based APIs like OpenAI, DeepSeek)';
COMMENT ON COLUMN usage.output_tokens IS 'Output tokens used (for token-based APIs like OpenAI, DeepSeek)';
COMMENT ON COLUMN usage.total_tokens IS 'Total tokens (input + output) or calculated equivalent';
COMMENT ON COLUMN usage.provider IS 'Service provider: openai, deepseek, exa, b2b_enrichment, perplexity, togetherai, etc.';
COMMENT ON COLUMN usage.model_name IS 'Actual model name from API response (e.g., gpt-4o, deepseek-chat, exa-search)';
COMMENT ON COLUMN usage.usage_context IS 'Usage context: agent_run, direct_api, batch_processing';

COMMENT ON TABLE usage_summary IS 'Daily aggregated usage summaries automatically updated via triggers';
COMMENT ON VIEW daily_usage_stats IS 'Daily usage statistics view for analytics and reporting';

-- Example usage patterns:
-- 
-- Credit-based APIs (Exa, B2B Enrichment):
-- INSERT INTO usage (organization_id, session_id, provider, model_name, api_calls, usage_context, total_tokens) 
-- VALUES ('org_123', 'session_456', 'exa', 'exa-search-v1', 5, 'direct_api', 0);
-- 
-- Token-based APIs (OpenAI, DeepSeek) - Direct usage:
-- INSERT INTO usage (organization_id, session_id, provider, model_name, api_calls, input_tokens, output_tokens, total_tokens, usage_context)
-- VALUES ('org_123', 'session_456', 'deepseek', 'deepseek-chat', 1, 750, 500, 1250, 'direct_api');
-- 
-- Agent runs using OpenAI:
-- INSERT INTO usage (organization_id, session_id, provider, model_name, api_calls, input_tokens, output_tokens, total_tokens, usage_context, run_id, agent_id)
-- VALUES ('org_123', 'session_456', 'openai', 'gpt-4o', 1, 1000, 800, 1800, 'agent_run', 'run_789', 'analysis_agent'); 