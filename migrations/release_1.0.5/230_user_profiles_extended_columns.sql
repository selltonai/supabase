-- Migration: Add extended columns to user_profiles
-- Sprint: SP-30 (User Profiles)
-- These columns are referenced by the workspace members page, clerk webhook,
-- and org invites API but were never explicitly created via migration.

ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS display_name TEXT,
  ADD COLUMN IF NOT EXISTS position TEXT,
  ADD COLUMN IF NOT EXISTS avatar_url TEXT,
  ADD COLUMN IF NOT EXISTS phone_personal TEXT,
  ADD COLUMN IF NOT EXISTS region TEXT,
  ADD COLUMN IF NOT EXISTS language TEXT DEFAULT 'en',
  ADD COLUMN IF NOT EXISTS email_account_ids TEXT[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS calendar_provider TEXT,
  ADD COLUMN IF NOT EXISTS linkedin_account_id TEXT,
  ADD COLUMN IF NOT EXISTS whatsapp_account_id TEXT,
  ADD COLUMN IF NOT EXISTS assigned_phone_numbers TEXT[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS daily_send_limit INTEGER NOT NULL DEFAULT 50,
  ADD COLUMN IF NOT EXISTS can_purchase BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS autopilot_enabled BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS onboarding_completed BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS last_active_at TIMESTAMPTZ;

-- Create invitation_metadata table for the org invites flow
-- Used by: POST /api/org/invites, DELETE /api/org/invites/[id],
-- GET /api/org/members, and the Clerk webhook handleOrganizationMembershipCreated
CREATE TABLE IF NOT EXISTS invitation_metadata (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  invitation_id TEXT NOT NULL UNIQUE,
  organization_id TEXT NOT NULL,
  email_address TEXT NOT NULL,
  first_name TEXT,
  last_name TEXT,
  role TEXT NOT NULL DEFAULT 'org:member',
  position TEXT,
  phone_number TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_invitation_metadata_org_email
  ON invitation_metadata(organization_id, email_address);

ALTER TABLE invitation_metadata ENABLE ROW LEVEL SECURITY;
-- Service role only — no user-facing RLS needed

-- Note: Companies do NOT have a user_id column (unlike contacts/tasks).
-- Companies are assigned via explicit assigned_to_user_id set during:
-- 1. Campaign processing (save_campaign_processing_results sets campaign creator)
-- 2. Manual creation (POST /api/companies sets authenticated user)
-- No auto-sync trigger needed — assignment is always explicit.

-- Ensure all migration columns exist (idempotent)
ALTER TABLE contacts ADD COLUMN IF NOT EXISTS assigned_to_user_id TEXT;
ALTER TABLE companies ADD COLUMN IF NOT EXISTS assigned_to_user_id TEXT;
ALTER TABLE tasks ADD COLUMN IF NOT EXISTS assigned_to_user_id TEXT;

-- Ensure indexes exist
CREATE INDEX IF NOT EXISTS idx_contacts_assigned_to ON contacts(assigned_to_user_id) WHERE assigned_to_user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_companies_assigned_to ON companies(assigned_to_user_id) WHERE assigned_to_user_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_tasks_assigned_to ON tasks(assigned_to_user_id) WHERE assigned_to_user_id IS NOT NULL;

-- Usage tracking columns
ALTER TABLE usage ADD COLUMN IF NOT EXISTS user_id TEXT;
CREATE INDEX IF NOT EXISTS idx_usage_user ON usage(user_id) WHERE user_id IS NOT NULL;
