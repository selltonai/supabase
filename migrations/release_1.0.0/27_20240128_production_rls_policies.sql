-- Production-ready RLS policies for token usage analytics
-- This migration sets up secure RLS policies that work with service role access

-- Ensure RLS is enabled on all tables
ALTER TABLE agent_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE agent_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE token_usage_summary ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization_settings ENABLE ROW LEVEL SECURITY;

-- Drop all existing policies
DO $$ 
BEGIN
    -- Drop policies for agent_runs
    DROP POLICY IF EXISTS "Allow backend inserts to agent_runs" ON agent_runs;
    DROP POLICY IF EXISTS "Organizations can view their own runs" ON agent_runs;
    DROP POLICY IF EXISTS "Organizations can insert their own runs" ON agent_runs;
    DROP POLICY IF EXISTS "Authenticated users can insert runs for their org" ON agent_runs;
    DROP POLICY IF EXISTS "Authenticated users can update their org runs" ON agent_runs;
    DROP POLICY IF EXISTS "Authenticated users can view their org runs" ON agent_runs;
    DROP POLICY IF EXISTS "Service role bypass" ON agent_runs;
    DROP POLICY IF EXISTS "Users can manage agent_runs" ON agent_runs;

    -- Drop policies for agent_messages  
    DROP POLICY IF EXISTS "Allow backend inserts to agent_messages" ON agent_messages;
    DROP POLICY IF EXISTS "Organizations can view their own messages" ON agent_messages;
    DROP POLICY IF EXISTS "Organizations can insert their own messages" ON agent_messages;
    DROP POLICY IF EXISTS "Authenticated users can insert messages for their org" ON agent_messages;
    DROP POLICY IF EXISTS "Authenticated users can view their org messages" ON agent_messages;
    DROP POLICY IF EXISTS "Service role bypass" ON agent_messages;
    DROP POLICY IF EXISTS "Users can manage agent_messages" ON agent_messages;

    -- Drop policies for token_usage_summary
    DROP POLICY IF EXISTS "Organizations can view their own summaries" ON token_usage_summary;
    DROP POLICY IF EXISTS "Authenticated users can view their org summaries" ON token_usage_summary;
    DROP POLICY IF EXISTS "Service role bypass" ON token_usage_summary;
    DROP POLICY IF EXISTS "Users can view token_usage_summary" ON token_usage_summary;
    DROP POLICY IF EXISTS "System can manage token_usage_summary" ON token_usage_summary;

    -- Drop policies for organization_settings
    DROP POLICY IF EXISTS "Organizations can view their own settings" ON organization_settings;
    DROP POLICY IF EXISTS "Organizations can update their own settings" ON organization_settings;
    DROP POLICY IF EXISTS "Organizations can insert their own settings" ON organization_settings;
    DROP POLICY IF EXISTS "Backend services can manage settings" ON organization_settings;
    DROP POLICY IF EXISTS "Authenticated users can manage their org settings" ON organization_settings;
    DROP POLICY IF EXISTS "Service role bypass" ON organization_settings;
    DROP POLICY IF EXISTS "Users can manage organization_settings" ON organization_settings;
EXCEPTION
    WHEN undefined_object THEN
        NULL;
END $$;

-- Create secure policies that deny all direct access
-- All operations must go through API routes that verify Clerk authentication

-- agent_runs policies - no direct access allowed
CREATE POLICY "No direct access to agent_runs"
    ON agent_runs FOR ALL
    USING (false)
    WITH CHECK (false);

-- agent_messages policies - no direct access allowed  
CREATE POLICY "No direct access to agent_messages"
    ON agent_messages FOR ALL
    USING (false)
    WITH CHECK (false);

-- token_usage_summary policies - no direct access allowed
CREATE POLICY "No direct access to token_usage_summary"
    ON token_usage_summary FOR ALL
    USING (false)
    WITH CHECK (false);

-- organization_settings policies - no direct access allowed
CREATE POLICY "No direct access to organization_settings"
    ON organization_settings FOR ALL
    USING (false)
    WITH CHECK (false);

-- Grant service role access (used by API routes)
-- The service role bypasses RLS completely, so no additional policies needed

-- Add comments explaining the security model
COMMENT ON TABLE agent_runs IS 'Access restricted to API routes using service role. Direct access blocked by RLS.';
COMMENT ON TABLE agent_messages IS 'Access restricted to API routes using service role. Direct access blocked by RLS.';
COMMENT ON TABLE token_usage_summary IS 'Access restricted to API routes using service role. Direct access blocked by RLS.';
COMMENT ON TABLE organization_settings IS 'Access restricted to API routes using service role. Direct access blocked by RLS.';

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_agent_runs_org_created 
    ON agent_runs(organization_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_agent_runs_org_model 
    ON agent_runs(organization_id, model_name);

CREATE INDEX IF NOT EXISTS idx_agent_messages_run_id 
    ON agent_messages(run_id);

CREATE INDEX IF NOT EXISTS idx_token_usage_summary_org_period 
    ON token_usage_summary(organization_id, period_start, period_end);

CREATE INDEX IF NOT EXISTS idx_organization_settings_org_id 
    ON organization_settings(organization_id);

-- Grant necessary permissions to the authenticated role (for Clerk users)
-- Even though RLS blocks access, we grant permissions to avoid permission errors
GRANT SELECT, INSERT, UPDATE, DELETE ON agent_runs TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON agent_messages TO authenticated;
GRANT SELECT ON token_usage_summary TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON organization_settings TO authenticated; 