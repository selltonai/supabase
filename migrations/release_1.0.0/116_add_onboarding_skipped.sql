-- Add onboarding_skipped field to track users who explicitly skip onboarding
ALTER TABLE organization_settings 
ADD COLUMN onboarding_skipped BOOLEAN DEFAULT FALSE,
ADD COLUMN onboarding_skipped_at TIMESTAMP WITH TIME ZONE;

-- Add index for faster queries
CREATE INDEX IF NOT EXISTS idx_organization_settings_onboarding_skipped ON organization_settings (onboarding_skipped);

-- Add comments for documentation
COMMENT ON COLUMN organization_settings.onboarding_skipped IS 'Whether the user explicitly skipped the onboarding flow';
COMMENT ON COLUMN organization_settings.onboarding_skipped_at IS 'When the onboarding was skipped';

-- Update existing comment for onboarding_completed
COMMENT ON COLUMN organization_settings.onboarding_completed IS 'Whether the user has completed the initial onboarding flow (not skipped)';