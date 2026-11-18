-- Migration 423's contract bootstrap: what 422 needs, then every table 423 reads, with the columns 423 reads under
-- their real names and types (latest definition in migrations/). Disposable database only.
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated; END IF;
END $$;
-- Supabase's default privileges: every new table and function is granted to anon and authenticated. Without these the
-- migration's revoke check would prove nothing.
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

-- release_1.0.0/1, 22; 115 (deleted), 302 (tier ... dispatch_suspended), 324 (work_access_mode), 379 (mobile, signup_source).
CREATE TABLE public."user" (
  id text PRIMARY KEY,
  created_at timestamptz DEFAULT timezone('utc', now()),
  email text
);
CREATE TABLE public.organization (
  id text PRIMARY KEY,
  created_at timestamptz DEFAULT timezone('utc', now()),
  name text,
  deleted boolean NOT NULL DEFAULT false,
  tier text NOT NULL DEFAULT 'starter',
  onboarding_mode text NOT NULL DEFAULT 'autonomous',
  activation_paid_at timestamptz,
  onboarding_status text NOT NULL DEFAULT 'pending',
  dispatch_suspended boolean NOT NULL DEFAULT false,
  work_access_mode text NOT NULL DEFAULT 'auto',
  mobile jsonb,
  signup_source text
);

-- release_1.0.0, as last re-declared by 300.
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

-- email_sequence_steps as 340 and 344 leave it (422 widens it).
CREATE TABLE public.email_sequence_steps (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  step_key text NOT NULL UNIQUE,
  name text NOT NULL,
  subject text NOT NULL,
  body text NOT NULL,
  is_active boolean NOT NULL DEFAULT false,
  audience_mode text NOT NULL DEFAULT 'not_activated',
  CONSTRAINT email_sequence_steps_audience_mode_check CHECK (audience_mode IN ('not_activated', 'funnel_stage'))
);

-- 22, 246 (role), 403 (canonical spelling; not enforced).
CREATE TABLE public.user_organizations (
  user_id text NOT NULL REFERENCES public."user"(id),
  organization_id text NOT NULL REFERENCES public.organization(id),
  role text DEFAULT 'org:member',
  PRIMARY KEY (user_id, organization_id)
);

-- 247 (one row per person and workspace), 399 (ui_seen).
CREATE TABLE public.user_profiles (
  user_id text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  timezone text NOT NULL DEFAULT 'UTC',
  notification_preferences jsonb NOT NULL DEFAULT '{}'::jsonb,
  ui_seen jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, organization_id)
);

-- 25, 49 (onboarding_completed_at), 409 (timezone), 414 (send window).
CREATE TABLE public.organization_settings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL UNIQUE REFERENCES public.organization(id) ON DELETE CASCADE,
  onboarding_completed boolean DEFAULT false,
  onboarding_completed_at timestamptz,
  timezone text,
  send_window_start smallint,
  send_window_end smallint,
  send_days smallint[]
);

-- 243, 371 (billing_started_at), 382 (web trial).
CREATE TABLE public.billing_customers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL UNIQUE REFERENCES public.organization(id) ON DELETE CASCADE,
  card_last4 text,
  card_brand text,
  status text NOT NULL DEFAULT 'active',
  monthly_spend_limit numeric(10,2),
  billing_started_at timestamptz,
  trial_started_at timestamptz,
  trial_ends_at timestamptz
);

-- 382, 384 (trial_product).
CREATE TABLE public.billing_credits (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  kind text NOT NULL CHECK (kind IN ('trial', 'referral', 'manual')),
  trial_product text,
  amount_usd numeric(10,2) NOT NULL CHECK (amount_usd > 0),
  remaining_usd numeric(10,2) NOT NULL CHECK (remaining_usd >= 0),
  source text,
  expires_at timestamptz,
  created_by text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- 243.
CREATE TABLE public.billing_invoices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  period_start timestamptz NOT NULL,
  period_end timestamptz NOT NULL,
  total numeric(10,2) NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'draft',
  paid_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- 304, 312 (is_active).
CREATE TABLE public.discount_codes (
  code text PRIMARY KEY,
  discount_type text NOT NULL CHECK (discount_type IN ('percentage', 'fixed_amount')),
  discount_value numeric NOT NULL,
  applies_to text NOT NULL DEFAULT 'activation' CHECK (applies_to IN ('activation', 'seats', 'tokens')),
  expires_at timestamptz,
  created_by text NOT NULL,
  is_active boolean NOT NULL DEFAULT true
);
CREATE TABLE public.discount_code_redemptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL REFERENCES public.discount_codes(code) ON DELETE RESTRICT,
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  redeemed_by text NOT NULL,
  redeemed_at timestamptz NOT NULL DEFAULT now()
);

-- release_1.0.5/1, 123 (sellton_cost).
CREATE TABLE public.usage (
  id bigserial PRIMARY KEY,
  organization_id text NOT NULL,
  session_id text NOT NULL,
  provider text NOT NULL,
  sellton_cost numeric(12,6) DEFAULT 0,
  created_at timestamptz DEFAULT now()
);

-- 306, 316 (is_billable, seat_type), 382 (phone trial and activation).
CREATE TABLE public.org_seats (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  clerk_user_id text NOT NULL,
  clerk_membership_id text NOT NULL UNIQUE,
  user_email text,
  seat_status text NOT NULL DEFAULT 'active' CHECK (seat_status IN ('active', 'suspended', 'terminated')),
  is_billable boolean NOT NULL DEFAULT true,
  seat_type text NOT NULL DEFAULT 'customer',
  mobile_trial_started_at timestamptz,
  mobile_trial_ends_at timestamptz,
  mobile_activated_at timestamptz
);

-- 38 (enums), 106-108 and 111, 113, 281 (task_type values), 330 (campaign_status values).
CREATE TYPE public.campaign_status AS ENUM ('draft', 'active', 'paused', 'completed', 'cancelled', 'discovery_completed', 'fully_completed');
CREATE TYPE public.task_type AS ENUM ('review_draft', 'meeting', 'company_verification', 'email_generation_processing', 'review_reply');
CREATE TYPE public.task_status AS ENUM ('pending', 'in_progress', 'completed', 'cancelled', 'scheduled');

-- 38, 81 (launched_at).
CREATE TABLE public.campaigns (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  user_id text NOT NULL,
  name text NOT NULL,
  status public.campaign_status DEFAULT 'draft',
  created_at timestamptz DEFAULT now(),
  started_at timestamptz,
  launched_at timestamptz
);

-- 33.
CREATE TABLE public.contacts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  name text NOT NULL,
  email text
);

-- 38, 106 (user_id dropped), 176 (created_by_user_id nullable), 181 (body).
CREATE TABLE public.tasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  created_by_user_id text,
  title text NOT NULL,
  task_type public.task_type NOT NULL,
  status public.task_status DEFAULT 'pending',
  contact_id uuid REFERENCES public.contacts(id) ON DELETE SET NULL,
  campaign_id uuid REFERENCES public.campaigns(id) ON DELETE SET NULL,
  body text,
  completed_at timestamptz,
  completed_by_user_id text,
  metadata jsonb DEFAULT '{}',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- 38, 281 (classification).
CREATE TABLE public.campaign_emails (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id uuid NOT NULL REFERENCES public.campaigns(id) ON DELETE CASCADE,
  contact_id uuid NOT NULL REFERENCES public.contacts(id) ON DELETE CASCADE,
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  subject text,
  content text,
  sent_at timestamptz,
  replied_at timestamptz,
  reply_content text,
  classification jsonb,
  created_at timestamptz DEFAULT now()
);

-- 254.
CREATE TABLE public.linkedin_accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL,
  user_id text NOT NULL,
  unipile_account_id text NOT NULL UNIQUE,
  provider text NOT NULL DEFAULT 'LINKEDIN',
  display_name text,
  status text NOT NULL DEFAULT 'connecting'
    CHECK (status IN ('connecting', 'active', 'disconnected', 'credentials_expired', 'restricted', 'error')),
  connected_at timestamptz NOT NULL DEFAULT now(),
  disconnected_at timestamptz,
  last_status_change_at timestamptz NOT NULL DEFAULT now()
);

-- 255, 269 (campaign_id).
CREATE TABLE public.linkedin_action_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL,
  user_id text NOT NULL,
  linkedin_account_id uuid NOT NULL REFERENCES public.linkedin_accounts(id) ON DELETE CASCADE,
  unipile_account_id text NOT NULL,
  action_type text NOT NULL CHECK (action_type IN ('invitation', 'message', 'comment', 'profile_view', 'post')),
  recipient_provider_id text,
  success boolean NOT NULL,
  campaign_id uuid,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- 28.
CREATE TABLE public.organization_files (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL,
  file_name text NOT NULL,
  file_type text NOT NULL,
  file_url text NOT NULL,
  file_size integer NOT NULL,
  uploaded_at timestamptz DEFAULT now(),
  uploaded_by text NOT NULL
);

-- 300, 313 (fit_type, is_supported).
CREATE TABLE public.onboarding_research (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL UNIQUE REFERENCES public.organization(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'researching',
  interview_call_id text,
  error_message text,
  fit_type text,
  is_supported boolean,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- 308.
CREATE TABLE public.onboarding_reengagement_sends (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  user_email text NOT NULL,
  sequence_step text NOT NULL,
  sent_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, sequence_step)
);

-- 340.
CREATE TABLE public.email_broadcasts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  subject text NOT NULL,
  body text NOT NULL
);
CREATE TABLE public.email_broadcast_sends (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  broadcast_id uuid NOT NULL REFERENCES public.email_broadcasts(id) ON DELETE CASCADE,
  organization_id text REFERENCES public.organization(id) ON DELETE SET NULL,
  user_email text NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'sent', 'failed', 'suppressed')),
  sent_at timestamptz,
  UNIQUE (broadcast_id, user_email)
);

-- 391.
CREATE TABLE public.customer_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  user_id text NOT NULL,
  type text NOT NULL CHECK (type IN ('feedback', 'mailboxes', 'leave')),
  status text NOT NULL DEFAULT 'new' CHECK (status IN ('new', 'in_progress', 'done')),
  body text,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- 341.
CREATE TABLE public.backoffice_org_notes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  body text NOT NULL,
  created_by text,
  archived_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- 316.
CREATE TABLE public.support_workspace_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  support_user_id text NOT NULL,
  support_user_email text NOT NULL,
  reason text,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'revoked', 'expired')),
  expires_at timestamptz NOT NULL,
  revoked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
