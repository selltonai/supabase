CREATE ROLE anon; CREATE ROLE authenticated; CREATE ROLE service_role BYPASSRLS;
CREATE TYPE public.task_type AS ENUM ('review_draft','meeting','company_verification','manual_outreach','nurture_reminder','linkedin_connect','follow_up','custom');
CREATE TYPE public.task_status AS ENUM ('pending','in_progress','completed','cancelled','scheduled','failed','in_review');
CREATE TABLE public."user" (id text PRIMARY KEY);
CREATE TABLE public.user_organizations (user_id text, organization_id text);
CREATE TABLE public.contacts (id uuid PRIMARY KEY, organization_id text, name text, phone text, do_not_contact boolean, unsubscribed_at timestamptz, automation_hold_at timestamptz, automation_hold_reason text, ooo_until timestamptz, open_to_work boolean, stop_drafts boolean);
CREATE TABLE public.deals (id uuid PRIMARY KEY, organization_id text, company_id uuid, primary_contact_id uuid, owner_user_id text, source_campaign_id uuid, stage text, closed_at timestamptz, stage_updated_at timestamptz);
CREATE TABLE public.company_contacts (organization_id text, company_id uuid, contact_id uuid);
CREATE TABLE public.contact_notes (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), organization_id text, contact_id uuid, user_id text, content text, note_type text, is_pinned boolean);
CREATE TABLE public.deal_activities (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), deal_id uuid, organization_id text, activity_type text, actor text, actor_user_id text, contact_id uuid, title text, metadata jsonb, bumps_last_activity boolean, created_at timestamptz DEFAULT now());
CREATE TABLE public.tasks (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), organization_id text, created_by_user_id text, title text, description text, status public.task_status DEFAULT 'pending', priority text, contact_id uuid REFERENCES public.contacts(id) ON DELETE SET NULL, campaign_id uuid, company_id uuid, assigned_to_user_id text, pre_generated_copy text, body text, subject text, due_date timestamptz, completed_at timestamptz, completed_by_user_id text, metadata jsonb DEFAULT '{}', created_at timestamptz DEFAULT now(), updated_at timestamptz DEFAULT now(), task_type public.task_type, scheduled boolean DEFAULT false, send_status text DEFAULT 'not_sent');
CREATE TABLE public.notifications (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), type text CONSTRAINT notifications_type_check CHECK(type IN ('task_assigned','deal_created','linkedin_campaign_account_missing')));

CREATE TABLE public.organization_settings (organization_id text PRIMARY KEY, crm_automation_enabled boolean NOT NULL DEFAULT false);

CREATE TABLE public.organization (id text PRIMARY KEY);
