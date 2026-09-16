-- Minimal disposable-only base schema; billing and analytics definitions below
-- are installed from their actual repository migrations by the test runner.
CREATE ROLE anon;
CREATE ROLE authenticated;
CREATE ROLE service_role BYPASSRLS;
CREATE TABLE public.organization (id text PRIMARY KEY);
CREATE TABLE public.usage (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), organization_id text,
  session_id text, provider text, model_name text, api_calls integer,
  input_tokens integer, output_tokens integer, total_tokens integer,
  campaign_id text, user_id text, run_id text, created_at timestamptz,
  metadata jsonb, original_cost numeric, sellton_cost numeric
);
GRANT SELECT ON public.usage TO service_role;
