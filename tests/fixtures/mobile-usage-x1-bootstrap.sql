-- KAN-333 X1 contract bootstrap, applied after usage-display-bootstrap.sql. Disposable database only.
-- Adds what 394 to 397 touch, shaped as on stage (2026-10-14): usage's remaining columns, its allow-all policy and the
-- grants 394 revokes, a view over usage, usage_summary with the live recounting trigger, action_label_map, the three
-- identical (organization_id, created_at DESC) indexes, organization and campaigns.
ALTER TABLE public.usage
  ADD COLUMN IF NOT EXISTS agent_id text,
  ADD COLUMN IF NOT EXISTS description text,
  ADD COLUMN IF NOT EXISTS tracking_start timestamptz DEFAULT now(),
  ADD COLUMN IF NOT EXISTS tracking_end timestamptz DEFAULT now(),
  ADD COLUMN IF NOT EXISTS usage_context text DEFAULT 'direct_api',
  ADD COLUMN IF NOT EXISTS original_pricing jsonb DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS sellton_pricing jsonb DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS user_email text,
  ADD COLUMN IF NOT EXISTS invoice_id uuid;

ALTER TABLE public.usage ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow all operations on usage" ON public.usage FOR ALL USING (true);
GRANT ALL ON TABLE public.usage TO anon, authenticated, service_role;
CREATE INDEX IF NOT EXISTS idx_usage_org_created ON public.usage USING btree (organization_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_usage_org_created_desc ON public.usage USING btree (organization_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_usage_org_period ON public.usage USING btree (organization_id, created_at DESC);

-- A view owned by the migration role and not security_invoker reads usage past RLS, as the 15 on stage do.
CREATE OR REPLACE VIEW public.usage_cost_daily AS
  SELECT organization_id, date(created_at) AS day, sum(sellton_cost) AS sellton_cost FROM public.usage GROUP BY 1, 2;
GRANT ALL ON TABLE public.usage_cost_daily TO anon, authenticated, service_role;

CREATE TABLE IF NOT EXISTS public.usage_summary (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL,
  provider text NOT NULL,
  model_name text,
  date date NOT NULL,
  total_api_calls integer DEFAULT 0,
  total_input_tokens integer DEFAULT 0,
  total_output_tokens integer DEFAULT 0,
  total_tokens integer DEFAULT 0,
  unique_sessions integer DEFAULT 0,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE (organization_id, provider, model_name, date)
);
ALTER TABLE public.usage_summary ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow all operations on usage_summary" ON public.usage_summary FOR ALL USING (true);
GRANT ALL ON TABLE public.usage_summary TO anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.update_usage_summary()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
    INSERT INTO usage_summary (
        organization_id,
        provider,
        model_name,
        date,
        total_api_calls,
        total_input_tokens,
        total_output_tokens,
        total_tokens,
        unique_sessions
    ) VALUES (
        NEW.organization_id,
        NEW.provider,
        NEW.model_name,
        DATE(NEW.created_at),
        NEW.api_calls,
        NEW.input_tokens,
        NEW.output_tokens,
        NEW.total_tokens,
        1  -- This will be recalculated in the conflict resolution
    )
    ON CONFLICT (organization_id, provider, model_name, date)
    DO UPDATE SET
        total_api_calls = usage_summary.total_api_calls + NEW.api_calls,
        total_input_tokens = usage_summary.total_input_tokens + NEW.input_tokens,
        total_output_tokens = usage_summary.total_output_tokens + NEW.output_tokens,
        total_tokens = usage_summary.total_tokens + NEW.total_tokens,
        unique_sessions = (
            SELECT COUNT(DISTINCT session_id) 
            FROM usage 
            WHERE organization_id = NEW.organization_id 
            AND provider = NEW.provider 
            AND COALESCE(model_name, '') = COALESCE(NEW.model_name, '')
            AND DATE(created_at) = DATE(NEW.created_at)
        ),
        updated_at = NOW();
    
    RETURN NEW;
END;
$function$

;
CREATE TRIGGER update_usage_summary_trigger AFTER INSERT ON public.usage FOR EACH ROW EXECUTE FUNCTION update_usage_summary();

CREATE TABLE IF NOT EXISTS public.action_label_map (
  provider text NOT NULL DEFAULT '',
  service_name text NOT NULL DEFAULT '',
  model_name_pattern text NOT NULL DEFAULT '',
  requires_grounding boolean NOT NULL DEFAULT false,
  task_key text NOT NULL,
  display_label text NOT NULL,
  priority integer NOT NULL DEFAULT 100,
  PRIMARY KEY (provider, service_name, model_name_pattern, requires_grounding, task_key)
);
GRANT ALL ON TABLE public.action_label_map TO anon, authenticated, service_role;

CREATE TABLE IF NOT EXISTS public.organization (id text PRIMARY KEY);
CREATE TABLE IF NOT EXISTS public.campaigns (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), organization_id text, lead_source text);

-- The Supabase service_role bypasses RLS; the contract's must too, or 394 would look like it locked the server out.
ALTER ROLE service_role BYPASSRLS;
