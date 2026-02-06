-- Migration: Create default ICP profiles for all existing organizations
-- Created: 2025-01-XX
-- Purpose: Add a default ICP profile for every organization that doesn't have one
-- Description: Ensures all organizations have at least one default ICP profile

-- Create default ICP profile for organizations that don't have one
INSERT INTO public.icp_profiles (
    organization_id,
    name,
    description,
    is_default,
    criteria,
    boosts_penalties,
    created_at,
    updated_at
)
SELECT 
    o.id as organization_id,
    'Default Profile' as name,
    'Default Ideal Customer Profile configuration' as description,
    true as is_default,
    '{
        "industries": {
            "enabled": false,
            "isHardFilter": false,
            "weight": 3,
            "value": []
        },
        "company_size": {
            "enabled": true,
            "isHardFilter": false,
            "weight": 3,
            "value": {
                "min": 11,
                "max": 500
            }
        },
        "regions": {
            "enabled": false,
            "isHardFilter": false,
            "weight": 2,
            "value": {
                "primary": [],
                "secondary": []
            }
        },
        "job_titles": {
            "enabled": true,
            "isHardFilter": false,
            "weight": 3,
            "value": ["Founder", "CEO"]
        }
    }'::jsonb as criteria,
    '{}'::jsonb as boosts_penalties,
    NOW() as created_at,
    NOW() as updated_at
FROM public.organization o
WHERE NOT EXISTS (
    SELECT 1 
    FROM public.icp_profiles ip 
    WHERE ip.organization_id = o.id
)
AND o.deleted IS NOT TRUE;

-- Add comment
COMMENT ON TABLE public.icp_profiles IS 'Ideal Customer Profile configurations with weighted scoring criteria. Each organization should have at least one default profile.';

