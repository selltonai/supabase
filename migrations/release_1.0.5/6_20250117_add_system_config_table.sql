-- Migration: Add system_config table for system-wide configuration
-- Date: 2025-01-17
-- Description: Create a table to store system configuration including service account credentials

-- Create system_config table
CREATE TABLE IF NOT EXISTS system_config (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    key TEXT NOT NULL UNIQUE,
    value JSONB NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create index for faster key lookups
CREATE INDEX idx_system_config_key ON system_config(key);

-- Add RLS policies
ALTER TABLE system_config ENABLE ROW LEVEL SECURITY;

-- Only service role can access system config
CREATE POLICY service_role_all ON system_config
    FOR ALL 
    USING (auth.role() = 'service_role');

-- Insert example for Google service account (commented out - add your actual credentials)
-- INSERT INTO system_config (key, value, description) VALUES (
--     'google_service_account',
--     '{"type":"service_account","project_id":"your-project","private_key_id":"...","private_key":"-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n","client_email":"...@....iam.gserviceaccount.com","client_id":"...","auth_uri":"https://accounts.google.com/o/oauth2/auth","token_uri":"https://oauth2.googleapis.com/token","auth_provider_x509_cert_url":"https://www.googleapis.com/oauth2/v1/certs","client_x509_cert_url":"..."}'::jsonb,
--     'Google Cloud service account credentials for Pub/Sub access'
-- );

-- Function to update the updated_at timestamp
CREATE OR REPLACE FUNCTION update_system_config_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to automatically update updated_at
CREATE TRIGGER update_system_config_updated_at_trigger
    BEFORE UPDATE ON system_config
    FOR EACH ROW
    EXECUTE FUNCTION update_system_config_updated_at(); 