-- Migration to add icp_keywords column for custom keywords/tags
-- This allows users to add custom keywords to their ICP settings

-- Add the new column
ALTER TABLE public.organization_settings
  ADD COLUMN IF NOT EXISTS icp_keywords TEXT[] DEFAULT '{}';

-- Create index for better performance
CREATE INDEX IF NOT EXISTS idx_organization_settings_icp_keywords ON public.organization_settings USING GIN (icp_keywords);

-- Add comment for documentation
COMMENT ON COLUMN public.organization_settings.icp_keywords IS 'Custom keywords/tags for ICP targeting'; 

