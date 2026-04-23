-- Migration: Create notifications table for in-app and email notifications
-- Date: 2026-03-07

CREATE TABLE IF NOT EXISTS notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id TEXT NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
    user_id TEXT NOT NULL REFERENCES "user"(id) ON DELETE CASCADE,
    type TEXT NOT NULL CHECK (type IN (
        'task_assigned',
        'task_due',
        'contact_replied',
        'campaign_alert',
        'campaign_completed',
        'budget_warning',
        'budget_critical',
        'daily_briefing',
        'weekly_report',
        'approval_needed',
        'system_alert'
    )),
    title TEXT NOT NULL,
    body TEXT,
    action_url TEXT,
    entity_type TEXT,
    entity_id TEXT,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    channels TEXT[] NOT NULL DEFAULT ARRAY['in_app']::TEXT[],
    priority TEXT NOT NULL DEFAULT 'normal' CHECK (priority IN ('low', 'normal', 'high', 'urgent')),
    email_sent BOOLEAN NOT NULL DEFAULT FALSE,
    email_sent_at TIMESTAMPTZ,
    email_error TEXT,
    resend_message_id TEXT,
    read BOOLEAN NOT NULL DEFAULT FALSE,
    read_at TIMESTAMPTZ,
    dismissed BOOLEAN NOT NULL DEFAULT FALSE,
    dedup_key TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_notifications_user_unread_list
    ON notifications(user_id, organization_id, created_at DESC)
    WHERE read = FALSE AND dismissed = FALSE;

CREATE INDEX IF NOT EXISTS idx_notifications_user_unread_count
    ON notifications(user_id, organization_id)
    WHERE read = FALSE AND dismissed = FALSE;

CREATE INDEX IF NOT EXISTS idx_notifications_org_created_at
    ON notifications(organization_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_notifications_entity_lookup
    ON notifications(organization_id, entity_type, entity_id, created_at DESC)
    WHERE entity_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_notifications_created_at
    ON notifications(created_at);

CREATE INDEX IF NOT EXISTS idx_notifications_channels_gin
    ON notifications USING GIN (channels);

CREATE UNIQUE INDEX IF NOT EXISTS idx_notifications_user_dedup_key
    ON notifications(user_id, dedup_key)
    WHERE dedup_key IS NOT NULL;

ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their own notifications" ON notifications;
CREATE POLICY "Users can view their own notifications"
    ON notifications FOR SELECT
    USING (
        user_id = auth.uid()::text
        AND organization_id IN (
            SELECT organization_id
            FROM user_organizations
            WHERE user_id = auth.uid()::text
        )
    );

DROP POLICY IF EXISTS "Users can update their own notifications" ON notifications;
CREATE POLICY "Users can update their own notifications"
    ON notifications FOR UPDATE
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

DROP POLICY IF EXISTS "Backend services can manage notifications" ON notifications;
CREATE POLICY "Backend services can manage notifications"
    ON notifications FOR ALL
    USING (current_setting('request.jwt.claim.role', true) = 'service_role')
    WITH CHECK (current_setting('request.jwt.claim.role', true) = 'service_role');
