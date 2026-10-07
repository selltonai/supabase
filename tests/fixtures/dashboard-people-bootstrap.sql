-- KAN-322 FR-A11 / FR-A11b contract bootstrap: only the columns migration 387 reads. Disposable database only.
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated; END IF;
END $$;

CREATE TABLE public.campaigns (id uuid PRIMARY KEY, organization_id text NOT NULL, user_id text);
CREATE TABLE public.campaign_emails (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), organization_id text NOT NULL, campaign_id uuid, contact_id uuid,
  status text, sent_at timestamptz, created_at timestamptz NOT NULL DEFAULT now(), metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  message_id text, thread_id text
);
CREATE TABLE public.tasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), organization_id text NOT NULL, task_type text, send_status text,
  sent_at timestamptz, campaign_id uuid, contact_id uuid, metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  email_id text, thread_id text
);
CREATE TABLE public.email_reply_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), organization_id text NOT NULL, contact_id uuid, campaign_id uuid,
  received_at timestamptz NOT NULL
);
CREATE TABLE public.linkedin_threads (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), organization_id text NOT NULL, owner_user_id text NOT NULL,
  contact_id uuid, campaign_id uuid, unipile_chat_id text NOT NULL UNIQUE, counterpart_provider_id text, thread_origin text,
  linkedin_account_id uuid
);
CREATE TABLE public.linkedin_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), organization_id text NOT NULL, unipile_chat_id text,
  direction text NOT NULL, occurred_at timestamptz NOT NULL
);
CREATE TABLE public.campaign_contacts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), campaign_id uuid NOT NULL, contact_id uuid NOT NULL, organization_id text,
  linkedin_account_id uuid, relation_state text, created_at timestamptz NOT NULL DEFAULT now(), UNIQUE (campaign_id, contact_id)
);
CREATE TABLE public.linkedin_action_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), organization_id text NOT NULL, campaign_id uuid, action_type text NOT NULL,
  success boolean NOT NULL, counterpart_provider_id text, recipient_provider_id text
);
