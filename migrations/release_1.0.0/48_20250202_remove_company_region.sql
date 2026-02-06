-- Migration: Remove company region from organization_settings
-- Purpose: Remove region field from company_info JSONB as it's now handled in ICP settings
-- Date: 2025-02-02

-- Remove region field from existing company_info JSONB data
UPDATE organization_settings 
SET company_info = company_info - 'region'
WHERE company_info ? 'region';

-- Add comment for clarity
COMMENT ON COLUMN organization_settings.company_info IS 'Company information including website, LinkedIn profile, and description (region moved to ICP settings)'; 