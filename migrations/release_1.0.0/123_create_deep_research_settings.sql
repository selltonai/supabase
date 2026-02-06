-- Create deep research settings table
CREATE TABLE IF NOT EXISTS deep_research_settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id TEXT NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
    
    -- Provider settings (can select multiple)
    selected_providers TEXT[] NOT NULL DEFAULT '{}',
    
    -- Research type settings (can select multiple)
    selected_research_types TEXT[] NOT NULL DEFAULT '{}',
    
    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- Constraints
    UNIQUE(organization_id)
);

-- Create index for faster lookups
CREATE INDEX IF NOT EXISTS idx_deep_research_settings_org_id ON deep_research_settings(organization_id);

-- Enable RLS
ALTER TABLE deep_research_settings ENABLE ROW LEVEL SECURITY;

-- Create RLS policies
CREATE POLICY "Organizations can view their own deep research settings"
    ON deep_research_settings FOR SELECT
    USING (auth.jwt() ->> 'organization_id' = organization_id);

CREATE POLICY "Organizations can update their own deep research settings"
    ON deep_research_settings FOR UPDATE
    USING (auth.jwt() ->> 'organization_id' = organization_id)
    WITH CHECK (auth.jwt() ->> 'organization_id' = organization_id);

CREATE POLICY "Organizations can insert their own deep research settings"
    ON deep_research_settings FOR INSERT
    WITH CHECK (auth.jwt() ->> 'organization_id' = organization_id);

-- Allow backend services to manage settings
CREATE POLICY "Backend services can manage deep research settings"
    ON deep_research_settings FOR ALL
    USING (true)
    WITH CHECK (true);

-- Create updated_at trigger
CREATE OR REPLACE FUNCTION update_deep_research_settings_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_deep_research_settings_updated_at
    BEFORE UPDATE ON deep_research_settings
    FOR EACH ROW
    EXECUTE FUNCTION update_deep_research_settings_updated_at();

-- Add comments for documentation
COMMENT ON TABLE deep_research_settings IS 'Stores user preferences for deep research providers and research types';
COMMENT ON COLUMN deep_research_settings.selected_providers IS 'Array of selected providers: exa, perplexity';
COMMENT ON COLUMN deep_research_settings.selected_research_types IS 'Array of selected research types: company_overview, funding_history, recent_news, competitive_landscape, growth_signals, icp_analysis';