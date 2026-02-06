-- Migration: Remove Email Accounts Data from Supabase
-- Description: Removes all email account data since it's now stored in external database
-- Author: System
-- Date: 2025-01-16

BEGIN;

-- Step 1: Remove all data from email_accounts table
DELETE FROM email_accounts;

-- Step 2: Drop all email_accounts related triggers and functions
DROP TRIGGER IF EXISTS update_email_accounts_updated_at_trigger ON email_accounts;
DROP TRIGGER IF EXISTS ensure_single_default_email_account_trigger ON email_accounts;
DROP FUNCTION IF EXISTS update_email_accounts_updated_at();
DROP FUNCTION IF EXISTS ensure_single_default_email_account();

-- Step 3: Drop all indexes on email_accounts table
DROP INDEX IF EXISTS idx_email_accounts_org_id;
DROP INDEX IF EXISTS idx_email_accounts_user_id;
DROP INDEX IF EXISTS idx_email_accounts_email;
DROP INDEX IF EXISTS idx_email_accounts_status;
DROP INDEX IF EXISTS idx_email_accounts_provider;
DROP INDEX IF EXISTS idx_email_accounts_default;
DROP INDEX IF EXISTS idx_email_accounts_scopes;
DROP INDEX IF EXISTS idx_email_accounts_oauth_provider;

-- Step 4: Drop all RLS policies on email_accounts table
DROP POLICY IF EXISTS "Organizations can view their email accounts" ON email_accounts;
DROP POLICY IF EXISTS "Organizations can insert their email accounts" ON email_accounts;
DROP POLICY IF EXISTS "Organizations can update their email accounts" ON email_accounts;
DROP POLICY IF EXISTS "Organizations can delete their email accounts" ON email_accounts;
DROP POLICY IF EXISTS "Backend services can manage email accounts" ON email_accounts;

-- Step 5: Drop the email_accounts table entirely
DROP TABLE IF EXISTS email_accounts CASCADE;

-- Step 6: Log the completion (commented out - migration_log table doesn't exist)
-- INSERT INTO public.migration_log (migration_name, completed_at, description) 
-- VALUES (
--     '101_remove_email_accounts_data', 
--     NOW(), 
--     'Removed all email account data from Supabase - data now stored in external database'
-- ) ON CONFLICT DO NOTHING;

COMMIT;

-- Add comment
COMMENT ON SCHEMA public IS 'Email accounts data removed - now stored in external MongoDB database'; 