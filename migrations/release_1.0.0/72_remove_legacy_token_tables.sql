-- Manual Script: Remove Legacy Token Tables
-- Description: Removes the old token tracking tables (agent_runs, agent_messages, token_usage_summary) 
--              that have been replaced by the newer usage and usage_summary tables
-- 
-- IMPORTANT: Run this script in your Supabase SQL Editor or database console
-- 
-- Tables being removed:
-- - agent_runs
-- - agent_messages  
-- - token_usage_summary
-- 
-- The newer 'usage' and 'usage_summary' tables will continue to be used

-- Step 1: Drop the trigger first
DROP TRIGGER IF EXISTS update_token_summary_on_run ON agent_runs;

-- Step 2: Drop the function
DROP FUNCTION IF EXISTS update_token_usage_summary();

-- Step 3: Drop the tables (in order due to foreign key constraints)
DROP TABLE IF EXISTS agent_messages CASCADE;
DROP TABLE IF EXISTS agent_runs CASCADE; 
DROP TABLE IF EXISTS token_usage_summary CASCADE;

-- Step 4: Drop the enum type if it exists and is no longer used
DROP TYPE IF EXISTS agent_event_type;

-- Verification: Check that tables are removed
-- You can run these queries to verify the tables are gone:
-- SELECT table_name FROM information_schema.tables WHERE table_name IN ('agent_runs', 'agent_messages', 'token_usage_summary'); 
