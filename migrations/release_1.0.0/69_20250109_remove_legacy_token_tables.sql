-- Migration: Remove Legacy Token Tables
-- Description: Removes the old token tracking tables (agent_runs, agent_messages, token_usage_summary) 
--              that have been replaced by the newer usage and usage_summary tables
-- Author: System  
-- Date: 2025-01-09

-- Drop any triggers that depend on the function first
DROP TRIGGER IF EXISTS update_token_summary_on_run ON agent_runs;

-- Drop the function
DROP FUNCTION IF EXISTS update_token_usage_summary() CASCADE;

-- Drop the tables (in order due to foreign key constraints)
DROP TABLE IF EXISTS agent_messages CASCADE;
DROP TABLE IF EXISTS agent_runs CASCADE;
DROP TABLE IF EXISTS token_usage_summary CASCADE;

-- Drop the enum type if it exists and is no longer used
DROP TYPE IF EXISTS agent_event_type;

-- Note: The newer 'usage' and 'usage_summary' tables will continue to be used
-- for token analytics functionality 