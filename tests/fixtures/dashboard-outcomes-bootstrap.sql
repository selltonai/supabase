-- KAN-322 FR-A11i contract bootstrap: only the columns migration 406 reads. Disposable database only.
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated; END IF;
END $$;
-- As Supabase: new functions are executable by anon and authenticated unless revoked (the migration must revoke).
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon, authenticated;

CREATE TABLE public.campaigns (id uuid PRIMARY KEY, organization_id text NOT NULL, user_id text, channel_strategy text);
CREATE TABLE public.contacts (id uuid PRIMARY KEY, organization_id text NOT NULL, created_at timestamptz NOT NULL);
CREATE TABLE public.campaign_companies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), campaign_id uuid NOT NULL, company_id uuid NOT NULL, organization_id text,
  created_at timestamptz NOT NULL, blocked_by_icp boolean DEFAULT false
);
CREATE TABLE public.company_contacts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), company_id uuid NOT NULL, contact_id uuid NOT NULL, organization_id text NOT NULL
);
CREATE TABLE public.campaign_contacts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), campaign_id uuid NOT NULL, contact_id uuid NOT NULL, organization_id text,
  created_at timestamptz NOT NULL, UNIQUE (campaign_id, contact_id)
);
CREATE TABLE public.deals (
  id uuid PRIMARY KEY, organization_id text NOT NULL, primary_contact_id uuid, stage_contact_id uuid, owner_user_id text,
  stage text NOT NULL, amount numeric(14, 2), currency text NOT NULL DEFAULT 'USD', closed_at timestamptz
);
CREATE TABLE public.deal_activities (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), deal_id uuid NOT NULL, organization_id text NOT NULL,
  activity_type text NOT NULL, metadata jsonb NOT NULL DEFAULT '{}'::jsonb, created_at timestamptz NOT NULL
);
CREATE INDEX ON public.campaign_companies (campaign_id);
CREATE INDEX ON public.company_contacts (company_id);
CREATE INDEX ON public.campaign_contacts (campaign_id);
CREATE INDEX ON public.deal_activities (deal_id, created_at DESC);
CREATE INDEX ON public.deals (organization_id, owner_user_id, stage);
