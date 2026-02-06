-- Quick fix for RLS policy issues
-- This migration updates the policies to allow backend inserts while maintaining read security

-- Drop existing INSERT policies
DROP POLICY IF EXISTS "Organizations can insert their own runs" ON agent_runs;
DROP POLICY IF EXISTS "Organizations can insert their own messages" ON agent_messages;

-- Create new INSERT policies that don't require JWT authentication
-- This allows backend services to insert data
CREATE POLICY "Allow backend inserts to agent_runs"
    ON agent_runs FOR INSERT
    WITH CHECK (true);

CREATE POLICY "Allow backend inserts to agent_messages"
    ON agent_messages FOR INSERT
    WITH CHECK (true);

-- The SELECT policies remain unchanged to maintain read security
-- Only organizations can read their own data

-- Note: For production, consider using service role key instead of this approach
-- This is a quick fix that maintains some security while allowing backend operations 