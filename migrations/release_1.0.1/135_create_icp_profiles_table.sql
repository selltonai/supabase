-- Migration: Create ICP profiles table
-- Created: 2025-11-02
-- Purpose: Add ICP profiles table for managing multiple Ideal Customer Profile configurations per organization
-- Description: Allows organizations to create multiple named ICP profiles with hard/soft filters, weights, and score modifiers

-- Create icp_profiles table
CREATE TABLE IF NOT EXISTS public.icp_profiles (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  organization_id TEXT NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  name TEXT NOT NULL CHECK (char_length(name) >= 1 AND char_length(name) <= 255),
  description TEXT,
  is_default BOOLEAN DEFAULT false,
  criteria JSONB DEFAULT '{}'::jsonb,
  boosts_penalties JSONB DEFAULT '{}'::jsonb,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  
  -- Ensure unique profile names per organization
  UNIQUE(organization_id, name)
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_icp_profiles_organization_id 
  ON public.icp_profiles(organization_id);

CREATE INDEX IF NOT EXISTS idx_icp_profiles_organization_default 
  ON public.icp_profiles(organization_id, is_default) 
  WHERE is_default = true;

CREATE INDEX IF NOT EXISTS idx_icp_profiles_created_at 
  ON public.icp_profiles(created_at DESC);

-- Create updated_at trigger function (if not exists)
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to automatically update updated_at
DROP TRIGGER IF EXISTS update_icp_profiles_updated_at ON public.icp_profiles;
CREATE TRIGGER update_icp_profiles_updated_at
  BEFORE UPDATE ON public.icp_profiles
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- Enable RLS
ALTER TABLE public.icp_profiles ENABLE ROW LEVEL SECURITY;

-- Create RLS policies
-- Users can view their organization's ICP profiles
DROP POLICY IF EXISTS "Users can view their organization's ICP profiles" ON public.icp_profiles;
CREATE POLICY "Users can view their organization's ICP profiles"
  ON public.icp_profiles
  FOR SELECT
  USING (
    organization_id IN (
      SELECT id FROM public.organization WHERE id = organization_id
    )
  );

-- Users can insert ICP profiles for their organization
DROP POLICY IF EXISTS "Users can insert ICP profiles for their organization" ON public.icp_profiles;
CREATE POLICY "Users can insert ICP profiles for their organization"
  ON public.icp_profiles
  FOR INSERT
  WITH CHECK (
    organization_id IN (
      SELECT id FROM public.organization WHERE id = organization_id
    )
  );

-- Users can update their organization's ICP profiles
DROP POLICY IF EXISTS "Users can update their organization's ICP profiles" ON public.icp_profiles;
CREATE POLICY "Users can update their organization's ICP profiles"
  ON public.icp_profiles
  FOR UPDATE
  USING (
    organization_id IN (
      SELECT id FROM public.organization WHERE id = organization_id
    )
  );

-- Users can delete their organization's ICP profiles
DROP POLICY IF EXISTS "Users can delete their organization's ICP profiles" ON public.icp_profiles;
CREATE POLICY "Users can delete their organization's ICP profiles"
  ON public.icp_profiles
  FOR DELETE
  USING (
    organization_id IN (
      SELECT id FROM public.organization WHERE id = organization_id
    )
  );

-- Add comments for documentation
COMMENT ON TABLE public.icp_profiles IS 'Ideal Customer Profile configurations with weighted scoring criteria';
COMMENT ON COLUMN public.icp_profiles.id IS 'Unique identifier for the ICP profile';
COMMENT ON COLUMN public.icp_profiles.organization_id IS 'Organization that owns this profile';
COMMENT ON COLUMN public.icp_profiles.name IS 'Profile name (1-255 characters, unique per organization)';
COMMENT ON COLUMN public.icp_profiles.description IS 'Optional description of the profile';
COMMENT ON COLUMN public.icp_profiles.is_default IS 'Whether this is the default profile for the organization';
COMMENT ON COLUMN public.icp_profiles.criteria IS 'JSONB object containing criterion configurations (industries, company_size, regions, etc.)';
COMMENT ON COLUMN public.icp_profiles.boosts_penalties IS 'JSONB object containing score modifiers (case_study_match_boost, recent_funding_boost, etc.)';

-- Add icp_profile_id column to campaigns table
ALTER TABLE campaigns 
ADD COLUMN IF NOT EXISTS icp_profile_id UUID REFERENCES public.icp_profiles(id) ON DELETE SET NULL;

-- Create index for campaign ICP profile lookup
CREATE INDEX IF NOT EXISTS idx_campaigns_icp_profile_id 
  ON campaigns(icp_profile_id) 
  WHERE icp_profile_id IS NOT NULL;

-- Add comment
COMMENT ON COLUMN campaigns.icp_profile_id IS 'Link to ICP profile used for this campaign';

