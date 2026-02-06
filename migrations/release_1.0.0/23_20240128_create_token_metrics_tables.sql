-- Create enum for event types if not exists
DO $$ BEGIN
    CREATE TYPE agent_event_type AS ENUM ('RunResponse', 'MessageResponse', 'ToolResponse');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- Create table for agent runs
CREATE TABLE IF NOT EXISTS agent_runs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id TEXT NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
    run_id TEXT NOT NULL,
    agent_id TEXT NOT NULL,
    session_id TEXT NOT NULL,
    model_name TEXT NOT NULL,
    content TEXT,
    content_type TEXT,
    event agent_event_type,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    run_created_at BIGINT,
    
    -- Token metrics aggregates
    total_input_tokens INTEGER DEFAULT 0,
    total_output_tokens INTEGER DEFAULT 0,
    total_tokens INTEGER DEFAULT 0,
    total_audio_tokens INTEGER DEFAULT 0,
    total_cached_tokens INTEGER DEFAULT 0,
    total_reasoning_tokens INTEGER DEFAULT 0,
    total_prompt_tokens INTEGER DEFAULT 0,
    total_completion_tokens INTEGER DEFAULT 0,
    total_processing_time DECIMAL(10, 3) DEFAULT 0,
    
    -- Raw metrics data (JSONB for flexibility)
    metrics_raw JSONB,
    
    UNIQUE(organization_id, run_id)
);

-- Create table for individual messages within runs
CREATE TABLE IF NOT EXISTS agent_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    run_id UUID NOT NULL REFERENCES agent_runs(id) ON DELETE CASCADE,
    organization_id TEXT NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
    role TEXT NOT NULL,
    content TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    message_created_at BIGINT,
    
    -- Message-level token metrics
    input_tokens INTEGER DEFAULT 0,
    output_tokens INTEGER DEFAULT 0,
    total_tokens INTEGER DEFAULT 0,
    audio_tokens INTEGER DEFAULT 0,
    input_audio_tokens INTEGER DEFAULT 0,
    output_audio_tokens INTEGER DEFAULT 0,
    cached_tokens INTEGER DEFAULT 0,
    reasoning_tokens INTEGER DEFAULT 0,
    prompt_tokens INTEGER DEFAULT 0,
    completion_tokens INTEGER DEFAULT 0,
    processing_time DECIMAL(10, 3),
    time_to_first_token DECIMAL(10, 3),
    
    -- Raw metrics data
    metrics_raw JSONB,
    prompt_tokens_details JSONB,
    completion_tokens_details JSONB
);

-- Create table for tracking token metrics by time period
CREATE TABLE IF NOT EXISTS token_usage_summary (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id TEXT NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
    model_name TEXT NOT NULL,
    period_start TIMESTAMP WITH TIME ZONE NOT NULL,
    period_end TIMESTAMP WITH TIME ZONE NOT NULL,
    total_runs INTEGER DEFAULT 0,
    total_input_tokens INTEGER DEFAULT 0,
    total_output_tokens INTEGER DEFAULT 0,
    total_tokens INTEGER DEFAULT 0,
    total_processing_time DECIMAL(10, 3) DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    UNIQUE(organization_id, model_name, period_start, period_end)
);

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_agent_runs_org_created ON agent_runs(organization_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_agent_runs_model ON agent_runs(organization_id, model_name);
CREATE INDEX IF NOT EXISTS idx_agent_runs_session ON agent_runs(session_id);
CREATE INDEX IF NOT EXISTS idx_agent_messages_run ON agent_messages(run_id);
CREATE INDEX IF NOT EXISTS idx_agent_messages_org ON agent_messages(organization_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_token_summary_org_period ON token_usage_summary(organization_id, period_start, period_end);

-- Create function to update token usage summary
CREATE OR REPLACE FUNCTION update_token_usage_summary()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO token_usage_summary (
        organization_id,
        model_name,
        period_start,
        period_end,
        total_runs,
        total_input_tokens,
        total_output_tokens,
        total_tokens,
        total_processing_time
    ) VALUES (
        NEW.organization_id,
        NEW.model_name,
        date_trunc('hour', NOW()),
        date_trunc('hour', NOW()) + interval '1 hour',
        1,
        NEW.total_input_tokens,
        NEW.total_output_tokens,
        NEW.total_tokens,
        NEW.total_processing_time
    )
    ON CONFLICT (organization_id, model_name, period_start, period_end)
    DO UPDATE SET
        total_runs = token_usage_summary.total_runs + 1,
        total_input_tokens = token_usage_summary.total_input_tokens + NEW.total_input_tokens,
        total_output_tokens = token_usage_summary.total_output_tokens + NEW.total_output_tokens,
        total_tokens = token_usage_summary.total_tokens + NEW.total_tokens,
        total_processing_time = token_usage_summary.total_processing_time + NEW.total_processing_time,
        updated_at = NOW();
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to automatically update summary
CREATE TRIGGER update_token_summary_on_run
    AFTER INSERT ON agent_runs
    FOR EACH ROW
    EXECUTE FUNCTION update_token_usage_summary();

-- Add RLS policies (if you're using Row Level Security)
ALTER TABLE agent_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE agent_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE token_usage_summary ENABLE ROW LEVEL SECURITY;

-- Create policies for organization-based access
CREATE POLICY "Organizations can view their own runs"
    ON agent_runs FOR SELECT
    USING (auth.jwt() ->> 'organization_id' = organization_id);

CREATE POLICY "Organizations can insert their own runs"
    ON agent_runs FOR INSERT
    WITH CHECK (auth.jwt() ->> 'organization_id' = organization_id);

CREATE POLICY "Organizations can view their own messages"
    ON agent_messages FOR SELECT
    USING (auth.jwt() ->> 'organization_id' = organization_id);

CREATE POLICY "Organizations can insert their own messages"
    ON agent_messages FOR INSERT
    WITH CHECK (auth.jwt() ->> 'organization_id' = organization_id);

CREATE POLICY "Organizations can view their own summaries"
    ON token_usage_summary FOR SELECT
    USING (auth.jwt() ->> 'organization_id' = organization_id); 