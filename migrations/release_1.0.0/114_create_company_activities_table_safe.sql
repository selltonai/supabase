-- Description: Create company_activities table (safe version)
-- This version handles cases where some objects might already exist

-- Create enum for activity types (only if it doesn't exist)
DO $$ BEGIN
    CREATE TYPE company_activity_type AS ENUM (
      'company_verification_approved',
      'company_verification_declined', 
      'note_added',
      'meeting_prepared',
      'contact_added',
      'campaign_added',
      'icp_score_updated',
      'company_updated'
    );
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- Create the company_activities table (only if it doesn't exist)
CREATE TABLE IF NOT EXISTS public.company_activities (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  organization_id text NOT NULL,
  company_id uuid NOT NULL,
  contact_id uuid NULL, -- Optional: if the activity is related to a specific contact
  campaign_id uuid NULL, -- Optional: if the activity is related to a specific campaign
  task_id uuid NULL, -- Optional: if the activity is related to a specific task
  
  -- Activity details
  activity_type company_activity_type NOT NULL,
  title text NOT NULL,
  description text NULL,
  
  -- User who performed the action
  created_by_user_id text NOT NULL,
  
  -- Metadata for additional context
  metadata jsonb NULL DEFAULT '{}'::jsonb,
  
  -- Timestamps
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now()
);

-- Add primary key constraint if it doesn't exist
DO $$ BEGIN
    ALTER TABLE public.company_activities ADD CONSTRAINT company_activities_pkey PRIMARY KEY (id);
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- Add foreign key constraints if they don't exist
DO $$ BEGIN
    ALTER TABLE public.company_activities ADD CONSTRAINT company_activities_organization_id_fkey 
      FOREIGN KEY (organization_id) REFERENCES organization (id) ON DELETE CASCADE;
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    ALTER TABLE public.company_activities ADD CONSTRAINT company_activities_company_id_fkey 
      FOREIGN KEY (company_id) REFERENCES companies (id) ON DELETE CASCADE;
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    ALTER TABLE public.company_activities ADD CONSTRAINT company_activities_contact_id_fkey 
      FOREIGN KEY (contact_id) REFERENCES contacts (id) ON DELETE SET NULL;
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    ALTER TABLE public.company_activities ADD CONSTRAINT company_activities_campaign_id_fkey 
      FOREIGN KEY (campaign_id) REFERENCES campaigns (id) ON DELETE SET NULL;
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    ALTER TABLE public.company_activities ADD CONSTRAINT company_activities_task_id_fkey 
      FOREIGN KEY (task_id) REFERENCES tasks (id) ON DELETE SET NULL;
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- Create indexes if they don't exist
CREATE INDEX IF NOT EXISTS idx_company_activities_organization_id 
  ON public.company_activities USING btree (organization_id);

CREATE INDEX IF NOT EXISTS idx_company_activities_company_id 
  ON public.company_activities USING btree (company_id);

CREATE INDEX IF NOT EXISTS idx_company_activities_contact_id 
  ON public.company_activities USING btree (contact_id);

CREATE INDEX IF NOT EXISTS idx_company_activities_campaign_id 
  ON public.company_activities USING btree (campaign_id);

CREATE INDEX IF NOT EXISTS idx_company_activities_task_id 
  ON public.company_activities USING btree (task_id);

CREATE INDEX IF NOT EXISTS idx_company_activities_activity_type 
  ON public.company_activities USING btree (activity_type);

CREATE INDEX IF NOT EXISTS idx_company_activities_created_at 
  ON public.company_activities USING btree (created_at DESC);

CREATE INDEX IF NOT EXISTS idx_company_activities_created_by_user_id 
  ON public.company_activities USING btree (created_by_user_id);

-- Create GIN index for metadata JSONB queries
CREATE INDEX IF NOT EXISTS idx_company_activities_metadata_gin 
  ON public.company_activities USING gin (metadata);

-- Create composite index for company + time-based queries
CREATE INDEX IF NOT EXISTS idx_company_activities_company_created_at 
  ON public.company_activities USING btree (company_id, created_at DESC);

-- Create trigger to update the updated_at column (only if the function exists)
DO $$ BEGIN
    IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'update_updated_at_column') THEN
        DROP TRIGGER IF EXISTS update_company_activities_updated_at ON company_activities;
        CREATE TRIGGER update_company_activities_updated_at 
          BEFORE UPDATE ON company_activities 
          FOR EACH ROW 
          EXECUTE FUNCTION update_updated_at_column();
    END IF;
END $$;

-- Enable RLS if not already enabled
DO $$ BEGIN
    ALTER TABLE company_activities ENABLE ROW LEVEL SECURITY;
EXCEPTION
    WHEN others THEN null;
END $$;

-- Drop existing policies if they exist and recreate them
DROP POLICY IF EXISTS "Users can view company activities for their organization" ON company_activities;
DROP POLICY IF EXISTS "Users can insert company activities for their organization" ON company_activities;
DROP POLICY IF EXISTS "Users can update their own company activities" ON company_activities;
DROP POLICY IF EXISTS "Users can delete their own company activities" ON company_activities;

-- Create RLS policies
CREATE POLICY "Users can view company activities for their organization" 
  ON company_activities FOR SELECT 
  USING (organization_id = current_setting('app.current_organization_id', true));

CREATE POLICY "Users can insert company activities for their organization" 
  ON company_activities FOR INSERT 
  WITH CHECK (organization_id = current_setting('app.current_organization_id', true));

CREATE POLICY "Users can update their own company activities" 
  ON company_activities FOR UPDATE 
  USING (
    organization_id = current_setting('app.current_organization_id', true) 
    AND created_by_user_id = current_setting('app.current_user_id', true)
  );

CREATE POLICY "Users can delete their own company activities" 
  ON company_activities FOR DELETE 
  USING (
    organization_id = current_setting('app.current_organization_id', true) 
    AND created_by_user_id = current_setting('app.current_user_id', true)
  ); 