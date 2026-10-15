-- KAN-322 FR-B8a contract bootstrap: only the columns migration 399 reads and writes. Disposable database only.
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated; END IF;
END $$;
-- As on Supabase: new functions are granted to anon and authenticated by default, so the migration's REVOKE is tested.
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon, authenticated;

CREATE TYPE public.task_type AS ENUM ('review_draft','meeting','company_verification','email_generation_processing','review_reply','nurture_reminder','linkedin_connect','manual_outreach');
CREATE TYPE public.task_status AS ENUM ('pending','in_progress','completed','cancelled','scheduled','failed','in_review');
CREATE TABLE public.tasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), organization_id text, status public.task_status DEFAULT 'pending',
  priority_rank integer, created_at timestamptz DEFAULT now(), campaign_id uuid, completed_by_user_id text,
  metadata jsonb DEFAULT '{}', task_type public.task_type
);
CREATE INDEX idx_tasks_campaign_id ON public.tasks (campaign_id);
CREATE INDEX idx_tasks_org_status_priority_created ON public.tasks (organization_id, status, priority_rank, created_at DESC);
CREATE TABLE public.user_profiles (
  user_id text NOT NULL, organization_id text NOT NULL, timezone text NOT NULL DEFAULT 'UTC',
  notification_preferences jsonb NOT NULL DEFAULT '{}', PRIMARY KEY (user_id, organization_id)
);
INSERT INTO public.user_profiles (user_id, organization_id) VALUES ('user_a', 'org_A');
