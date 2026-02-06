-- Fix RLS policies to allow authenticated users to insert/update data for their organization
-- This properly handles both JWT-based auth and service role access

-- Drop existing overly permissive policies
DROP POLICY IF EXISTS "Allow backend inserts to agent_runs" ON agent_runs;
DROP POLICY IF EXISTS "Allow backend inserts to agent_messages" ON agent_messages;
DROP POLICY IF EXISTS "Backend services can manage settings" ON organization_settings;

-- Create better policies for agent_runs
DROP POLICY IF EXISTS "Organizations can insert their own runs" ON agent_runs;
CREATE POLICY "Authenticated users can insert runs for their org"
    ON agent_runs FOR INSERT
    TO authenticated
    WITH CHECK (
        organization_id IN (
            SELECT o.id FROM organization o
            INNER JOIN user_organizations uo ON uo.organization_id = o.id
            WHERE uo.user_id = auth.uid()::text
        )
    );

-- Allow updates for own organization
CREATE POLICY "Authenticated users can update their org runs"
    ON agent_runs FOR UPDATE
    TO authenticated
    USING (
        organization_id IN (
            SELECT o.id FROM organization o
            INNER JOIN user_organizations uo ON uo.organization_id = o.id
            WHERE uo.user_id = auth.uid()::text
        )
    )
    WITH CHECK (
        organization_id IN (
            SELECT o.id FROM organization o
            INNER JOIN user_organizations uo ON uo.organization_id = o.id
            WHERE uo.user_id = auth.uid()::text
        )
    );

-- Fix the SELECT policy to use proper auth check
DROP POLICY IF EXISTS "Organizations can view their own runs" ON agent_runs;
CREATE POLICY "Authenticated users can view their org runs"
    ON agent_runs FOR SELECT
    TO authenticated
    USING (
        organization_id IN (
            SELECT o.id FROM organization o
            INNER JOIN user_organizations uo ON uo.organization_id = o.id
            WHERE uo.user_id = auth.uid()::text
        )
    );

-- Similar fixes for agent_messages
DROP POLICY IF EXISTS "Organizations can insert their own messages" ON agent_messages;
CREATE POLICY "Authenticated users can insert messages for their org"
    ON agent_messages FOR INSERT
    TO authenticated
    WITH CHECK (
        organization_id IN (
            SELECT o.id FROM organization o
            INNER JOIN user_organizations uo ON uo.organization_id = o.id
            WHERE uo.user_id = auth.uid()::text
        )
    );

DROP POLICY IF EXISTS "Organizations can view their own messages" ON agent_messages;
CREATE POLICY "Authenticated users can view their org messages"
    ON agent_messages FOR SELECT
    TO authenticated
    USING (
        organization_id IN (
            SELECT o.id FROM organization o
            INNER JOIN user_organizations uo ON uo.organization_id = o.id
            WHERE uo.user_id = auth.uid()::text
        )
    );

-- Fix organization_settings policies
DROP POLICY IF EXISTS "Organizations can insert their own settings" ON organization_settings;
CREATE POLICY "Authenticated users can manage their org settings"
    ON organization_settings FOR ALL
    TO authenticated
    USING (
        organization_id IN (
            SELECT o.id FROM organization o
            INNER JOIN user_organizations uo ON uo.organization_id = o.id
            WHERE uo.user_id = auth.uid()::text
        )
    )
    WITH CHECK (
        organization_id IN (
            SELECT o.id FROM organization o
            INNER JOIN user_organizations uo ON uo.organization_id = o.id
            WHERE uo.user_id = auth.uid()::text
        )
    );

-- Also allow service role to bypass RLS (for backend operations)
CREATE POLICY "Service role bypass" ON agent_runs
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

CREATE POLICY "Service role bypass" ON agent_messages
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

CREATE POLICY "Service role bypass" ON organization_settings
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

-- Fix token_usage_summary policies
DROP POLICY IF EXISTS "Organizations can view their own summaries" ON token_usage_summary;
CREATE POLICY "Authenticated users can view their org summaries"
    ON token_usage_summary FOR SELECT
    TO authenticated
    USING (
        organization_id IN (
            SELECT o.id FROM organization o
            INNER JOIN user_organizations uo ON uo.organization_id = o.id
            WHERE uo.user_id = auth.uid()::text
        )
    );

CREATE POLICY "Service role bypass" ON token_usage_summary
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true); 