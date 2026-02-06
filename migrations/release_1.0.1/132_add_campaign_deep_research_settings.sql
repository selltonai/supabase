-- Migration: Add deep research settings to campaigns table
-- Created: 2025-10-31
-- Purpose: Add campaign-level deep research configuration columns and set defaults for all existing campaigns
-- Description: Adds deep_research_provider, deep_research_types, and deep_research_override columns.
--              Sets all existing campaigns to use 'perplexity' (Sellton Research Agent) with all research types enabled.

-- Add deep_research_provider column (TEXT: 'none', 'exa', 'perplexity', or 'both')
ALTER TABLE campaigns 
ADD COLUMN IF NOT EXISTS deep_research_provider TEXT;

-- Add deep_research_types column (TEXT[]: array of research type strings)
ALTER TABLE campaigns 
ADD COLUMN IF NOT EXISTS deep_research_types TEXT[] DEFAULT '{}'::TEXT[];

-- Add deep_research_override column (BOOLEAN: true = use campaign settings, false/null = use org defaults)
ALTER TABLE campaigns 
ADD COLUMN IF NOT EXISTS deep_research_override BOOLEAN DEFAULT false;

-- Add comments for documentation
COMMENT ON COLUMN campaigns.deep_research_provider IS 'Deep research provider for this campaign: none, exa, perplexity, or both. If null, uses organization default.';
COMMENT ON COLUMN campaigns.deep_research_types IS 'Array of research types to enable: company_overview, funding_history, recent_news, competitive_landscape, growth_signals, icp_analysis. If empty, uses organization default.';
COMMENT ON COLUMN campaigns.deep_research_override IS 'If true, campaign uses its own deep research settings. If false or null, campaign inherits organization-level settings.';

-- Create index for faster lookups
CREATE INDEX IF NOT EXISTS idx_campaigns_deep_research_provider 
    ON campaigns(deep_research_provider) 
    WHERE deep_research_provider IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_campaigns_deep_research_override 
    ON campaigns(deep_research_override) 
    WHERE deep_research_override = true;

-- Update ALL existing campaigns to use Sellton Research Agent (perplexity) with all research types
-- This sets the default for all campaigns, ensuring consistent deep research configuration
UPDATE campaigns
SET 
    deep_research_provider = 'perplexity',
    deep_research_types = ARRAY[
        'company_overview',
        'funding_history',
        'recent_news',
        'competitive_landscape',
        'growth_signals',
        'icp_analysis'
    ],
    deep_research_override = true;

-- Log the update
DO $$
DECLARE
    updated_count INTEGER;
    total_campaigns INTEGER;
BEGIN
    SELECT COUNT(*) INTO total_campaigns FROM campaigns;
    SELECT COUNT(*) INTO updated_count FROM campaigns WHERE deep_research_override = true;
    RAISE NOTICE 'Total campaigns: %, Updated with deep research settings: %', total_campaigns, updated_count;
    RAISE NOTICE 'All campaigns now have default deep research settings: perplexity provider with all research types enabled';
END $$;

