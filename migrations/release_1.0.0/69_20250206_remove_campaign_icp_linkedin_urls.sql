-- Migration: Remove campaign_icp_linkedin_urls table
-- Date: 2025-02-06
-- Description: Remove the campaign_icp_linkedin_urls table as it's no longer needed

-- Drop the table
DROP TABLE IF EXISTS public.campaign_icp_linkedin_urls;

-- Note: No need to drop constraints as they are automatically dropped with the table 