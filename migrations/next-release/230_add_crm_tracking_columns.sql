-- Add tracking columns for CRM Import functionality
-- These columns are needed to track the source of companies and contacts
-- and the discovery method used

-- =====================================================
-- COMPANIES TABLE - Add missing columns
-- =====================================================

-- Add source column to track where company data came from
-- Values: 'campaign', 'crm_import', 'manual', 'api'
ALTER TABLE public.companies 
ADD COLUMN IF NOT EXISTS source TEXT;

COMMENT ON COLUMN public.companies.source IS 'Source of company data: campaign, crm_import, manual, api';

-- Add discovery_method column to track how company was discovered
-- Values: 'basic_extraction', 'ai_research', 'b2b_database', 'enrichment_api'
ALTER TABLE public.companies 
ADD COLUMN IF NOT EXISTS discovery_method TEXT;

COMMENT ON COLUMN public.companies.discovery_method IS 'Method used to discover company data: basic_extraction, ai_research, b2b_database, enrichment_api';

-- =====================================================
-- CONTACTS TABLE - Add missing columns
-- =====================================================

-- Add source column to track where contact data came from
-- Values: 'campaign', 'crm_import', 'manual', 'api'
ALTER TABLE public.contacts 
ADD COLUMN IF NOT EXISTS source TEXT;

COMMENT ON COLUMN public.contacts.source IS 'Source of contact data: campaign, crm_import, manual, api';

-- Add discovery_method column to track how contact was discovered
-- Values: 'basic_extraction', 'ai_research', 'b2b_database', 'enrichment_api'
ALTER TABLE public.contacts 
ADD COLUMN IF NOT EXISTS discovery_method TEXT;

COMMENT ON COLUMN public.contacts.discovery_method IS 'Method used to discover contact data: basic_extraction, ai_research, b2b_database, enrichment_api';

-- =====================================================
-- Add social_profiles column to contacts (JSONB for flexibility)
-- =====================================================

ALTER TABLE public.contacts 
ADD COLUMN IF NOT EXISTS social_profiles JSONB DEFAULT '{}'::jsonb;

COMMENT ON COLUMN public.contacts.social_profiles IS 'Social media profiles: {twitter: url, github: url, etc.}';

-- =====================================================
-- Create indexes for performance (optional but recommended)
-- =====================================================

CREATE INDEX IF NOT EXISTS idx_companies_source ON public.companies(source);
CREATE INDEX IF NOT EXISTS idx_companies_discovery_method ON public.companies(discovery_method);
CREATE INDEX IF NOT EXISTS idx_contacts_source ON public.contacts(source);
CREATE INDEX IF NOT EXISTS idx_contacts_discovery_method ON public.contacts(discovery_method);

-- =====================================================
-- Summary
-- =====================================================
-- This migration adds tracking columns to companies and contacts tables
-- to support CRM Import functionality and data source tracking.
-- 
-- Columns added:
-- - companies.source (TEXT)
-- - companies.discovery_method (TEXT)
-- - contacts.source (TEXT)
-- - contacts.discovery_method (TEXT)
-- - contacts.social_profiles (JSONB)
