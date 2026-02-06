-- Create organization_settings table for storing various organization-specific settings
CREATE TABLE IF NOT EXISTS organization_settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id TEXT NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
    
    -- Token usage alerts settings
    token_alerts JSONB DEFAULT '{
        "dailyThreshold": 1000000,
        "weeklyThreshold": 5000000,
        "monthlyThreshold": 20000000,
        "emailEnabled": true,
        "slackEnabled": false
    }'::jsonb,
    
    -- Other settings can be added here as JSONB columns
    general_settings JSONB DEFAULT '{}'::jsonb,
    notification_settings JSONB DEFAULT '{}'::jsonb,
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    UNIQUE(organization_id)
);

-- Create index for faster lookups
CREATE INDEX IF NOT EXISTS idx_organization_settings_org_id ON organization_settings(organization_id);

-- Enable RLS
ALTER TABLE organization_settings ENABLE ROW LEVEL SECURITY;

-- Create RLS policies
CREATE POLICY "Organizations can view their own settings"
    ON organization_settings FOR SELECT
    USING (auth.jwt() ->> 'organization_id' = organization_id);

CREATE POLICY "Organizations can update their own settings"
    ON organization_settings FOR UPDATE
    USING (auth.jwt() ->> 'organization_id' = organization_id)
    WITH CHECK (auth.jwt() ->> 'organization_id' = organization_id);

CREATE POLICY "Organizations can insert their own settings"
    ON organization_settings FOR INSERT
    WITH CHECK (auth.jwt() ->> 'organization_id' = organization_id);

-- Allow backend services to insert/update settings
CREATE POLICY "Backend services can manage settings"
    ON organization_settings FOR ALL
    USING (true)
    WITH CHECK (true);

-- Create function to update the updated_at timestamp
CREATE OR REPLACE FUNCTION update_organization_settings_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to automatically update updated_at
CREATE TRIGGER update_organization_settings_updated_at_trigger
    BEFORE UPDATE ON organization_settings
    FOR EACH ROW
    EXECUTE FUNCTION update_organization_settings_updated_at(); 