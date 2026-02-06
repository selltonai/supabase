-- Add onboarding completion tracking to organization_settings
ALTER TABLE organization_settings 
ADD COLUMN onboarding_completed BOOLEAN DEFAULT FALSE,
ADD COLUMN onboarding_completed_at TIMESTAMP WITH TIME ZONE;

-- Add index for faster queries
CREATE INDEX idx_organization_settings_onboarding ON organization_settings (onboarding_completed);

-- Add comment for documentation
COMMENT ON COLUMN organization_settings.onboarding_completed IS 'Whether the user has completed or skipped the initial onboarding flow';
COMMENT ON COLUMN organization_settings.onboarding_completed_at IS 'When the onboarding was marked as completed'; 