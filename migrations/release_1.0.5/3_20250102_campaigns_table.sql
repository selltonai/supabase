-- Campaigns Table Migration
-- This migration creates a 'campaigns' table for storing campaign data

-- Create campaigns table
CREATE TABLE IF NOT EXISTS campaigns (
    id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    organization_id TEXT NOT NULL,
    name TEXT NOT NULL,
    description TEXT,
    target_audience TEXT,
    industry TEXT,
    company_size TEXT,
    location TEXT,
    
    -- JSON fields for flexible data storage
    pain_points JSONB DEFAULT '[]'::jsonb,
    keywords JSONB DEFAULT '[]'::jsonb,
    target_audience_data JSONB DEFAULT '{}'::jsonb,
    campaign_data JSONB DEFAULT '{}'::jsonb,
    
    -- Timestamps
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    -- Foreign key constraint (if organizations table exists)
    CONSTRAINT fk_campaigns_organization 
        FOREIGN KEY (organization_id) 
        REFERENCES organization(id) 
        ON DELETE CASCADE
);

-- Add columns if they don't exist (for existing tables)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'campaigns') THEN
        ALTER TABLE campaigns ADD COLUMN IF NOT EXISTS target_audience TEXT;
        ALTER TABLE campaigns ADD COLUMN IF NOT EXISTS industry TEXT;
        ALTER TABLE campaigns ADD COLUMN IF NOT EXISTS company_size TEXT;
        ALTER TABLE campaigns ADD COLUMN IF NOT EXISTS location TEXT;
        ALTER TABLE campaigns ADD COLUMN IF NOT EXISTS pain_points JSONB DEFAULT '[]'::jsonb;
        ALTER TABLE campaigns ADD COLUMN IF NOT EXISTS keywords JSONB DEFAULT '[]'::jsonb;
        ALTER TABLE campaigns ADD COLUMN IF NOT EXISTS target_audience_data JSONB DEFAULT '{}'::jsonb;
        ALTER TABLE campaigns ADD COLUMN IF NOT EXISTS campaign_data JSONB DEFAULT '{}'::jsonb;
    END IF;
END $$;

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_campaigns_organization_id ON campaigns(organization_id);
CREATE INDEX IF NOT EXISTS idx_campaigns_created_at ON campaigns(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_campaigns_name ON campaigns(name);
CREATE INDEX IF NOT EXISTS idx_campaigns_industry ON campaigns(industry);

-- Enable RLS (Row Level Security)
ALTER TABLE campaigns ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Allow all operations on campaigns" ON campaigns;

-- Simple policy that allows all operations (adjust based on your auth setup)
CREATE POLICY "Allow all operations on campaigns" ON campaigns FOR ALL USING (true);

-- Grant permissions
GRANT ALL ON campaigns TO service_role;

-- Add comments for documentation
COMMENT ON TABLE campaigns IS 'Campaign data for company research and targeting';
COMMENT ON COLUMN campaigns.id IS 'Unique campaign identifier (UUID)';
COMMENT ON COLUMN campaigns.organization_id IS 'Reference to organization that owns this campaign';
COMMENT ON COLUMN campaigns.name IS 'Campaign name/title';
COMMENT ON COLUMN campaigns.description IS 'Campaign description';
COMMENT ON COLUMN campaigns.target_audience IS 'Target audience description';
COMMENT ON COLUMN campaigns.industry IS 'Target industry';
COMMENT ON COLUMN campaigns.company_size IS 'Target company size (e.g., "50-500 employees")';
COMMENT ON COLUMN campaigns.location IS 'Target geographic location';
COMMENT ON COLUMN campaigns.pain_points IS 'JSON array of pain points addressed by campaign';
COMMENT ON COLUMN campaigns.keywords IS 'JSON array of relevant keywords';
COMMENT ON COLUMN campaigns.target_audience_data IS 'JSON object with detailed target audience data';
COMMENT ON COLUMN campaigns.campaign_data IS 'JSON object for additional campaign-specific data';

-- Example usage:
-- 
-- Insert a new campaign:
-- INSERT INTO campaigns (organization_id, name, description, industry, company_size, location, pain_points, keywords)
-- VALUES (
--     'org_123', 
--     'SaaS Growth Campaign', 
--     'Find companies that need our SaaS solution',
--     'Software Development',
--     '50-500 employees',
--     'United States, Europe',
--     '["Manual processes", "Scalability issues", "Integration challenges"]'::jsonb,
--     '["SaaS", "software", "automation", "integration", "API"]'::jsonb
-- );
-- 
-- Query campaigns for an organization:
-- SELECT * FROM campaigns WHERE organization_id = 'org_123' ORDER BY created_at DESC;
-- 
-- Get campaign as JSON map:
-- SELECT 
--     id, name, description, industry, company_size, location,
--     pain_points, keywords, target_audience_data, campaign_data,
--     created_at, updated_at
-- FROM campaigns 
-- WHERE id = 'campaign_123' AND organization_id = 'org_123'; 