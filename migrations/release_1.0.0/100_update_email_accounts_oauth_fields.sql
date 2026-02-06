-- Migration: Update email_accounts table for complete OAuth data storage
-- Description: Updates email_accounts table to store all OAuth data from Gmail authentication
-- Author: System
-- Date: 2025-01-16

-- Add token_expiry column if not exists (in addition to expires_at)
ALTER TABLE email_accounts 
ADD COLUMN IF NOT EXISTS token_expiry TIMESTAMPTZ;

-- Change scope column to store array of scopes instead of single text
ALTER TABLE email_accounts 
DROP COLUMN IF EXISTS scope;

ALTER TABLE email_accounts 
ADD COLUMN IF NOT EXISTS scopes TEXT[] DEFAULT '{}';

-- Add firstname and lastname columns (main user name fields)
ALTER TABLE email_accounts 
ADD COLUMN IF NOT EXISTS firstname TEXT;

ALTER TABLE email_accounts 
ADD COLUMN IF NOT EXISTS lastname TEXT;

-- Remove deprecated name columns
ALTER TABLE email_accounts 
DROP COLUMN IF EXISTS name;

ALTER TABLE email_accounts 
DROP COLUMN IF EXISTS given_name;

ALTER TABLE email_accounts 
DROP COLUMN IF EXISTS family_name;

ALTER TABLE email_accounts 
DROP COLUMN IF EXISTS first_name;   

ALTER TABLE email_accounts 
DROP COLUMN IF EXISTS last_name;

-- Remove email authentication columns (SPF, DKIM, DMARC)
ALTER TABLE email_accounts 
DROP COLUMN IF EXISTS spf_record;

ALTER TABLE email_accounts 
DROP COLUMN IF EXISTS spf_status;

ALTER TABLE email_accounts 
DROP COLUMN IF EXISTS dkim_record;

ALTER TABLE email_accounts 
DROP COLUMN IF EXISTS dkim_status;

ALTER TABLE email_accounts 
DROP COLUMN IF EXISTS dmarc_record;

ALTER TABLE email_accounts 
DROP COLUMN IF EXISTS dmarc_status;

-- Add columns for better OAuth tracking
ALTER TABLE email_accounts 
ADD COLUMN IF NOT EXISTS oauth_provider TEXT DEFAULT 'google'; -- google, microsoft, etc.

ALTER TABLE email_accounts 
ADD COLUMN IF NOT EXISTS oauth_raw_response JSONB; -- Store complete OAuth response for debugging

-- Add index on scopes for better querying
CREATE INDEX IF NOT EXISTS idx_email_accounts_scopes ON email_accounts USING GIN(scopes);

-- Add index on oauth_provider
CREATE INDEX IF NOT EXISTS idx_email_accounts_oauth_provider ON email_accounts(oauth_provider);

-- Update comments
COMMENT ON COLUMN email_accounts.token_expiry IS 'Token expiry timestamp from OAuth provider (original format)';
COMMENT ON COLUMN email_accounts.scopes IS 'Array of OAuth scopes granted by the user';
COMMENT ON COLUMN email_accounts.firstname IS 'First name from OAuth provider';
COMMENT ON COLUMN email_accounts.lastname IS 'Last name from OAuth provider';
COMMENT ON COLUMN email_accounts.oauth_provider IS 'OAuth provider used for authentication';
COMMENT ON COLUMN email_accounts.oauth_raw_response IS 'Complete OAuth response for debugging purposes'; 