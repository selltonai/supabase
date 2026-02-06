-- Migration: Remove deep_research_settings table
-- Created: 2025-10-31
-- Purpose: Remove organization-level deep research settings table as deep research is now configured at campaign level
-- Description: Drops the deep_research_settings table and all associated indexes/constraints.
--              Deep research settings are now stored directly in the campaigns table.

-- ============================================================================
-- STEP 1: Drop indexes
-- ============================================================================

DROP INDEX IF EXISTS idx_deep_research_settings_org_id;

-- ============================================================================
-- STEP 2: Drop the table
-- ============================================================================

DROP TABLE IF EXISTS deep_research_settings CASCADE;

-- ============================================================================
-- STEP 3: Log the cleanup
-- ============================================================================

DO $$
BEGIN
    RAISE NOTICE 'Successfully removed deep_research_settings table';
    RAISE NOTICE 'Deep research settings are now configured at the campaign level';
    RAISE NOTICE 'All campaigns use their own deep_research_provider and deep_research_types columns';
END $$;















