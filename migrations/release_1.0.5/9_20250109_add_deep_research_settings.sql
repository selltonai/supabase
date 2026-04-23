-- Migration: Add deep_research_settings table
-- Created: 2025-01-09
-- Purpose: Store organization-level configuration for deep research providers and research types

-- Create function to update updated_at timestamp if it doesn't exist
CREATE OR REPLACE FUNCTION update_deep_research_settings_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create deep_research_settings table
CREATE TABLE IF NOT EXISTS public.deep_research_settings (
    id UUID NOT NULL DEFAULT gen_random_uuid(),
    organization_id TEXT NOT NULL,
    selected_providers TEXT[] NOT NULL DEFAULT '{}'::TEXT[],
    selected_research_types TEXT[] NOT NULL DEFAULT '{}'::TEXT[],
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Primary key constraint
    CONSTRAINT deep_research_settings_pkey PRIMARY KEY (id),
    
    -- Unique constraint on organization_id
    CONSTRAINT deep_research_settings_organization_id_key UNIQUE (organization_id),
    
    -- Foreign key constraint
    CONSTRAINT deep_research_settings_organization_id_fkey 
        FOREIGN KEY (organization_id) 
        REFERENCES organization (id) 
        ON DELETE CASCADE
) TABLESPACE pg_default;

-- Create index for organization_id
CREATE INDEX IF NOT EXISTS idx_deep_research_settings_org_id 
    ON public.deep_research_settings 
    USING btree (organization_id) 
    TABLESPACE pg_default;

-- Create trigger to update updated_at timestamp
DROP TRIGGER IF EXISTS update_deep_research_settings_updated_at ON deep_research_settings;
CREATE TRIGGER update_deep_research_settings_updated_at 
    BEFORE UPDATE ON deep_research_settings 
    FOR EACH ROW
    EXECUTE FUNCTION update_deep_research_settings_updated_at();

-- Add comment to table
COMMENT ON TABLE public.deep_research_settings IS 'Organization-level configuration for deep research providers and research types';

-- Add comments to columns
COMMENT ON COLUMN public.deep_research_settings.selected_providers IS 'Array of selected providers: none, exa, perplexity. Use "none" to disable deep research entirely';
COMMENT ON COLUMN public.deep_research_settings.selected_research_types IS 'Array of selected research types: company_overview, funding_history, recent_news, competitive_landscape, growth_signals, icp_analysis. Empty array when provider is "none"';
