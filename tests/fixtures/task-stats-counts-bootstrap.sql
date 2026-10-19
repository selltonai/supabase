-- KAN-322 FR-B5e contract bootstrap: the columns 386 and 408 read, with the production enums. Disposable database only.
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated; END IF;
END $$;

-- As on the Supabase image: functions created in public are granted to anon and authenticated by default, so a
-- migration must revoke them explicitly. Without this line the contract's grant check would prove nothing.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon, authenticated;

CREATE TYPE public.task_status AS ENUM ('pending', 'in_progress', 'completed', 'cancelled', 'scheduled', 'failed', 'in_review');
CREATE TYPE public.task_type AS ENUM ('review_draft', 'review_reply', 'meeting', 'company_verification',
  'email_generation_processing', 'nurture_reminder', 'linkedin_connect', 'manual_outreach', 'call');
CREATE TABLE public.campaigns (id uuid PRIMARY KEY, organization_id text, status text);
CREATE TABLE public.contacts (id uuid PRIMARY KEY, do_not_contact boolean NOT NULL DEFAULT false);
CREATE TABLE public.campaign_companies (campaign_id uuid, company_id uuid, organization_id text, status text);
CREATE TABLE public.tasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL,
  task_type public.task_type,
  status public.task_status DEFAULT 'pending',
  priority text,
  contact_id uuid,
  campaign_id uuid,
  company_id uuid,
  deal_id uuid,
  assigned_to_user_id text,
  due_date timestamptz,
  metadata jsonb DEFAULT '{}'::jsonb,
  conversation_summary jsonb DEFAULT '{}'::jsonb
);
