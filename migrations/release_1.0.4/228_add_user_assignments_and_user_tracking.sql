-- Contacts: add assigned user
ALTER TABLE contacts ADD COLUMN assigned_to_user_id TEXT REFERENCES "user"(id) ON DELETE SET NULL;
CREATE INDEX idx_contacts_assigned ON contacts(assigned_to_user_id) WHERE assigned_to_user_id IS NOT NULL;

-- Companies: add assigned user
ALTER TABLE companies ADD COLUMN assigned_to_user_id TEXT REFERENCES "user"(id) ON DELETE SET NULL;
CREATE INDEX idx_companies_assigned ON companies(assigned_to_user_id) WHERE assigned_to_user_id IS NOT NULL;

-- Tasks: add assigned_to (separate from created_by)
ALTER TABLE tasks ADD COLUMN assigned_to_user_id TEXT REFERENCES "user"(id) ON DELETE SET NULL;
CREATE INDEX idx_tasks_assigned ON tasks(assigned_to_user_id) WHERE assigned_to_user_id IS NOT NULL;

-- Campaigns: user_id already exists (creator). Add visibility flag.
-- Campaigns remain org-visible for Managers+, but Members see only their own.

-- Email accounts (Gmail API / MongoDB): add user_id field
-- This is in MongoDB, not Supabase — requires Gmail API code change

-- Usage tracking: add user_id
ALTER TABLE token_usage ADD COLUMN user_id TEXT REFERENCES "user"(id) ON DELETE SET NULL;
CREATE INDEX idx_token_usage_user ON token_usage(user_id) WHERE user_id IS NOT NULL;

ALTER TABLE usage_summary ADD COLUMN user_id TEXT;





CREATE TABLE user_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id TEXT NOT NULL REFERENCES "user"(id) ON DELETE CASCADE,
    organization_id TEXT NOT NULL REFERENCES organization(id) ON DELETE CASCADE,

    -- Personal Info
    display_name TEXT,
    position TEXT,              -- 'SDR', 'AE', 'Manager', 'VP Sales', 'Admin', etc.
    avatar_url TEXT,
    phone_personal TEXT,        -- Personal phone (not Sellton-provisioned)

    -- Preferences
    timezone TEXT DEFAULT 'UTC',
    region TEXT,                -- User's region (e.g., 'Europe', 'NA')
    language TEXT DEFAULT 'en',
    notification_preferences JSONB DEFAULT '{
        "email_reminders": true,
        "task_notifications": true,
        "campaign_alerts": true,
        "daily_briefing": true,
        "weekly_report": true
    }',

    -- Channel connections (per-user)
    email_account_ids TEXT[] DEFAULT '{}',      -- Gmail/Microsoft account IDs connected by this user
    calendar_provider TEXT,                      -- 'cal_com' | 'calendly' | null
    calendar_credentials JSONB,                 -- Per-user calendar API key
    linkedin_account_id TEXT,                    -- Unipile account ID (future)
    whatsapp_account_id TEXT,                    -- Future
    assigned_phone_numbers TEXT[] DEFAULT '{}',  -- Telnyx phone numbers assigned by admin

    -- Settings
    daily_send_limit INTEGER DEFAULT 50,        -- Max emails this user can send per day
    can_purchase BOOLEAN DEFAULT false,          -- Whether this user can make purchases
    autopilot_enabled BOOLEAN DEFAULT true,      -- Whether autopilot can act on this user's behalf

    -- Status
    onboarding_completed BOOLEAN DEFAULT false,
    last_active_at TIMESTAMP,

    created_at TIMESTAMP DEFAULT now(),
    updated_at TIMESTAMP DEFAULT now(),

    UNIQUE(user_id, organization_id)
);

CREATE INDEX idx_user_profiles_org ON user_profiles(organization_id);
CREATE INDEX idx_user_profiles_user ON user_profiles(user_id);