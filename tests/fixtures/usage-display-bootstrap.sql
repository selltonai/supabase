-- KAN-322 FR-A12 contract bootstrap: public.usage with the columns 345 reads. Disposable database only.
-- The runner then applies 326's two helper functions and 345 itself before 388.
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated; END IF;
END $$;

-- As on the Supabase image: functions created in public are granted to anon and authenticated by default, so a
-- migration must revoke them explicitly. Without this line the contract's grant check would prove nothing.
-- service_role is left out on purpose, so that the migration's own GRANT to service_role is what the check sees.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon, authenticated;

CREATE TABLE public.usage (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL,
  session_id text NOT NULL,
  provider text NOT NULL,
  model_name text,
  api_calls integer DEFAULT 0,
  input_tokens integer DEFAULT 0,
  output_tokens integer DEFAULT 0,
  total_tokens integer DEFAULT 0,
  run_id text,
  user_id text,
  campaign_id text,
  created_at timestamptz DEFAULT now(),
  metadata jsonb DEFAULT '{}'::jsonb,
  original_cost numeric(12,6) DEFAULT 0,
  sellton_cost numeric(12,6) DEFAULT 0
);
