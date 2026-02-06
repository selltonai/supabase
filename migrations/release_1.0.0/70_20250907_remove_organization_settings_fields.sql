-- Migration: Remove deprecated fields from the organization_settings table
-- This migration drops several columns related to ICP and token alerts that are no longer in use.

BEGIN;

-- Drop the token_alerts JSONB field
ALTER TABLE public.organization_settings
DROP COLUMN IF EXISTS token_alerts;

-- Drop all ICP-related fields
ALTER TABLE public.organization_settings
DROP COLUMN IF EXISTS icp_min_employees,
DROP COLUMN IF EXISTS icp_max_employees,
DROP COLUMN IF EXISTS icp_sales_process,
DROP COLUMN IF EXISTS icp_industries,
DROP COLUMN IF EXISTS icp_job_titles,
DROP COLUMN IF EXISTS icp_primary_regions,
DROP COLUMN IF EXISTS icp_secondary_regions,
DROP COLUMN IF EXISTS icp_focus_areas,
DROP COLUMN IF EXISTS icp_pain_points,
DROP COLUMN IF EXISTS icp_keywords;

COMMIT; 