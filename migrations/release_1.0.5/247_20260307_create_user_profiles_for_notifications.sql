-- Migration: Create user_profiles for notification preferences and scheduling
-- Date: 2026-03-07

CREATE TABLE IF NOT EXISTS user_profiles (
    user_id TEXT NOT NULL REFERENCES "user"(id) ON DELETE CASCADE,
    organization_id TEXT NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
    timezone TEXT NOT NULL DEFAULT 'UTC',
    notification_preferences JSONB NOT NULL DEFAULT '{
        "email_reminders": true,
        "task_notifications": true,
        "campaign_alerts": true,
        "daily_briefing": true,
        "weekly_report": true
    }'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, organization_id)
);

INSERT INTO user_profiles (user_id, organization_id)
SELECT user_id, organization_id
FROM user_organizations
ON CONFLICT (user_id, organization_id) DO NOTHING;

CREATE INDEX IF NOT EXISTS idx_user_profiles_organization_id
    ON user_profiles(organization_id);

ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their own user profile" ON user_profiles;
CREATE POLICY "Users can view their own user profile"
    ON user_profiles FOR SELECT
    USING (
        user_id = auth.uid()::text
        AND organization_id IN (
            SELECT organization_id
            FROM user_organizations
            WHERE user_id = auth.uid()::text
        )
    );

DROP POLICY IF EXISTS "Users can update their own user profile" ON user_profiles;
CREATE POLICY "Users can update their own user profile"
    ON user_profiles FOR UPDATE
    USING (
        user_id = auth.uid()::text
        AND organization_id IN (
            SELECT organization_id
            FROM user_organizations
            WHERE user_id = auth.uid()::text
        )
    )
    WITH CHECK (
        user_id = auth.uid()::text
        AND organization_id IN (
            SELECT organization_id
            FROM user_organizations
            WHERE user_id = auth.uid()::text
        )
    );

DROP POLICY IF EXISTS "Backend services can manage user profiles" ON user_profiles;
CREATE POLICY "Backend services can manage user profiles"
    ON user_profiles FOR ALL
    USING (current_setting('request.jwt.claim.role', true) = 'service_role')
    WITH CHECK (current_setting('request.jwt.claim.role', true) = 'service_role');

CREATE OR REPLACE FUNCTION update_user_profiles_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_user_profiles_updated_at_trigger ON user_profiles;
CREATE TRIGGER update_user_profiles_updated_at_trigger
    BEFORE UPDATE ON user_profiles
    FOR EACH ROW
    EXECUTE FUNCTION update_user_profiles_updated_at();
