-- Create email_accounts table for storing email account configurations and OAuth data
CREATE TABLE IF NOT EXISTS email_accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id TEXT NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
    user_id TEXT REFERENCES "user"(id),
    
    -- Basic account information
    name TEXT NOT NULL, -- Display name for the account
    email_address TEXT NOT NULL, -- The actual email address
    provider TEXT NOT NULL DEFAULT 'gmail', -- gmail, outlook, smtp, etc.
    status TEXT NOT NULL DEFAULT 'inactive' CHECK (status IN ('active', 'inactive', 'pending', 'error')),
    
    -- OAuth credentials (Gmail/OAuth providers)
    access_token TEXT, -- OAuth access token
    refresh_token TEXT, -- OAuth refresh token  
    token_type TEXT DEFAULT 'Bearer', -- Usually Bearer
    expires_in INTEGER, -- Token expiration in seconds
    expires_at TIMESTAMP WITH TIME ZONE, -- Calculated expiration timestamp
    id_token TEXT, -- OpenID Connect ID token
    scope TEXT, -- OAuth scopes granted
    
    -- User profile data from OAuth
    google_user_id TEXT, -- Google's unique user identifier (sub claim)
    verified_email BOOLEAN DEFAULT false,
    given_name TEXT,
    family_name TEXT,
    picture TEXT, -- Profile picture URL
    locale TEXT,
    
    -- Email authentication settings (SPF, DKIM, DMARC)
    spf_record TEXT, -- SPF record for the domain
    spf_status TEXT DEFAULT 'unknown' CHECK (spf_status IN ('valid', 'invalid', 'unknown', 'not_configured')),
    dkim_record TEXT, -- DKIM record
    dkim_status TEXT DEFAULT 'unknown' CHECK (dkim_status IN ('valid', 'invalid', 'unknown', 'not_configured')),
    dmarc_record TEXT, -- DMARC record
    dmarc_status TEXT DEFAULT 'unknown' CHECK (dmarc_status IN ('valid', 'invalid', 'unknown', 'not_configured')),
    
    -- Additional configuration
    is_default BOOLEAN DEFAULT false, -- Is this the default sending account
    daily_send_limit INTEGER DEFAULT 100, -- Daily sending limit
    is_enabled BOOLEAN DEFAULT true,
    
    -- Metadata
    last_sync_at TIMESTAMP WITH TIME ZONE,
    last_error TEXT, -- Last error message if any
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- Constraints
    UNIQUE(organization_id, email_address),
    UNIQUE(organization_id, google_user_id) -- Prevent duplicate Google accounts per org
);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_email_accounts_org_id ON email_accounts(organization_id);
CREATE INDEX IF NOT EXISTS idx_email_accounts_user_id ON email_accounts(user_id);
CREATE INDEX IF NOT EXISTS idx_email_accounts_email ON email_accounts(email_address);
CREATE INDEX IF NOT EXISTS idx_email_accounts_status ON email_accounts(status);
CREATE INDEX IF NOT EXISTS idx_email_accounts_provider ON email_accounts(provider);
CREATE INDEX IF NOT EXISTS idx_email_accounts_default ON email_accounts(organization_id, is_default) WHERE is_default = true;

-- Enable RLS
ALTER TABLE email_accounts ENABLE ROW LEVEL SECURITY;

-- Create RLS policies
CREATE POLICY "Organizations can view their email accounts"
    ON email_accounts FOR SELECT
    USING (auth.jwt() ->> 'organization_id' = organization_id);

CREATE POLICY "Organizations can insert their email accounts"
    ON email_accounts FOR INSERT
    WITH CHECK (auth.jwt() ->> 'organization_id' = organization_id);

CREATE POLICY "Organizations can update their email accounts"
    ON email_accounts FOR UPDATE
    USING (auth.jwt() ->> 'organization_id' = organization_id)
    WITH CHECK (auth.jwt() ->> 'organization_id' = organization_id);

CREATE POLICY "Organizations can delete their email accounts"
    ON email_accounts FOR DELETE
    USING (auth.jwt() ->> 'organization_id' = organization_id);

-- Backend services policy
CREATE POLICY "Backend services can manage email accounts"
    ON email_accounts FOR ALL
    USING (true)
    WITH CHECK (true);

-- Create function to update the updated_at timestamp
CREATE OR REPLACE FUNCTION update_email_accounts_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to automatically update updated_at
CREATE TRIGGER update_email_accounts_updated_at_trigger
    BEFORE UPDATE ON email_accounts
    FOR EACH ROW
    EXECUTE FUNCTION update_email_accounts_updated_at();

-- Create function to ensure only one default account per organization
CREATE OR REPLACE FUNCTION ensure_single_default_email_account()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.is_default = true THEN
        -- Set all other accounts for this organization to not default
        UPDATE email_accounts 
        SET is_default = false 
        WHERE organization_id = NEW.organization_id 
        AND id != NEW.id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to ensure only one default account
CREATE TRIGGER ensure_single_default_email_account_trigger
    BEFORE INSERT OR UPDATE ON email_accounts
    FOR EACH ROW
    WHEN (NEW.is_default = true)
    EXECUTE FUNCTION ensure_single_default_email_account();

-- Add helpful comments
COMMENT ON TABLE email_accounts IS 'Stores email account configurations for sending campaigns and managing inboxes';
COMMENT ON COLUMN email_accounts.name IS 'Display name for the email account (e.g., "Sales Team", "Support")';
COMMENT ON COLUMN email_accounts.email_address IS 'The actual email address';
COMMENT ON COLUMN email_accounts.provider IS 'Email provider type: gmail, outlook, smtp, etc.';
COMMENT ON COLUMN email_accounts.status IS 'Account status: active, inactive, pending, error';
COMMENT ON COLUMN email_accounts.access_token IS 'OAuth access token (encrypted in production)';
COMMENT ON COLUMN email_accounts.refresh_token IS 'OAuth refresh token (encrypted in production)';
COMMENT ON COLUMN email_accounts.google_user_id IS 'Google''s unique user identifier from OAuth';
COMMENT ON COLUMN email_accounts.spf_status IS 'SPF record validation status';
COMMENT ON COLUMN email_accounts.dkim_status IS 'DKIM record validation status';
COMMENT ON COLUMN email_accounts.dmarc_status IS 'DMARC record validation status';
COMMENT ON COLUMN email_accounts.is_default IS 'Whether this is the default sending account for the organization'; 