-- Migration: Remove Boosts & Penalties from Default ICP Profiles
-- Description: Removes boosts_penalties from all default ICP profiles (boosts & penalties feature removed)
-- Author: System
-- Date: 2025-01-XX

-- Update all default ICP profiles to remove boosts_penalties
UPDATE public.icp_profiles
SET boosts_penalties = '{}'::jsonb,
    updated_at = NOW()
WHERE is_default = true
  AND boosts_penalties IS NOT NULL
  AND boosts_penalties != '{}'::jsonb;

-- Add comment
COMMENT ON COLUMN public.icp_profiles.boosts_penalties IS 'Boosts and penalties for ICP scoring (deprecated - kept for backward compatibility but should be empty)';

