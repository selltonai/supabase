-- KAN-322 FR-B7 contract bootstrap: only what migration 398 reads. Disposable database only.
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated; END IF;
END $$;
-- Supabase's default privileges: every new function is granted to anon and authenticated. Without these the
-- migration's revoke check would prove nothing.
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
CREATE TABLE public.linkedin_threads (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL,
  unipile_chat_id text NOT NULL UNIQUE,
  last_direction text CHECK (last_direction IN ('inbound', 'outbound')),
  last_message_at timestamptz
);
CREATE TABLE public.linkedin_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL,
  unipile_chat_id text,
  direction text NOT NULL CHECK (direction IN ('inbound', 'outbound')),
  occurred_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_linkedin_messages_chat ON public.linkedin_messages(unipile_chat_id, occurred_at ASC) WHERE unipile_chat_id IS NOT NULL;
