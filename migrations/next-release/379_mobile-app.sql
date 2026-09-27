-- 379 — Mobile app (M1): the mobile service's columns and tables.
--
-- Why: the Sellton mobile app (selltonai-mobile) sets up orgs, runs plays and sends and
-- answers email from the phone. It needs two columns on organization (its mobile settings,
-- and where the org was created) and three tables of its own: the phone's chat thread, its
-- scheduled work, and its daily send counters. It touches no table that holds customer data:
-- the Brain links on companies and contacts ship with the Brain cutover (KAN-270).
--
-- Affected projects:
--   - selltonai-mobile: the only writer and reader of everything below.
--   - selltonai / selltonai-modal: none. No web cron or page reads the new tables.
-- Deploy together: apply before the mobile service is given the stage service-role key, and
-- before the web's Clerk webhook writes organization.signup_source.
--
-- Additive + non-breaking. Safe to drop while empty.

-- The org's mobile settings (jsonb; no spend limit in here).
ALTER TABLE public.organization ADD COLUMN IF NOT EXISTS mobile jsonb;

-- Where the org was created, for the mobile service and billing.
ALTER TABLE public.organization ADD COLUMN IF NOT EXISTS signup_source text;
COMMENT ON COLUMN public.organization.signup_source IS
  '''mobile'' | ''web''; NULL = web; written by the web Clerk webhook from Clerk metadata';

-- The phone's chat thread per play (append-only; not an email conversation).
CREATE TABLE IF NOT EXISTS public.play_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  play_id uuid NOT NULL REFERENCES public.campaigns(id) ON DELETE CASCADE,
  role text NOT NULL CHECK (role IN ('user', 'sellton')),
  text text,
  card jsonb,
  refs jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_play_messages_play_created ON public.play_messages (play_id, created_at);

-- Every piece of later work as a row; the worker claims a row once (pending → running).
CREATE TABLE IF NOT EXISTS public.mobile_scheduled_actions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  play_id uuid REFERENCES public.campaigns(id) ON DELETE CASCADE,
  contact_id uuid REFERENCES public.contacts(id) ON DELETE SET NULL,
  kind text NOT NULL,  -- send_email · plan_followups · send_followup · brain_poll · inbound · mailbox_connected · park_retry · signal_scan · signal · mailbox_status · mailbox_check
  due_at timestamptz NOT NULL,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'running', 'done', 'cancelled', 'failed')),
  attempts integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  payload jsonb,
  dedup_key text UNIQUE,  -- e.g. a Unipile event id; NULLs never collide
  last_error text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()  -- also the lease clock of a running row
);
CREATE INDEX IF NOT EXISTS idx_mobile_scheduled_actions_status_due ON public.mobile_scheduled_actions (status, due_at);
CREATE INDEX IF NOT EXISTS idx_mobile_scheduled_actions_org_play ON public.mobile_scheduled_actions (organization_id, play_id);

-- Emails sent per mailbox per day (the day is the user's, computed by the service).
CREATE TABLE IF NOT EXISTS public.mobile_send_counters (
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  account_id text NOT NULL,
  day date NOT NULL,
  count integer NOT NULL DEFAULT 0 CHECK (count >= 0),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (organization_id, account_id, day)
);

-- Reserve up to p_n sends for the day without passing p_cap; returns how many were reserved.
CREATE OR REPLACE FUNCTION public.mobile_reserve_sends(
  p_org text, p_account text, p_day date, p_n integer, p_cap integer
) RETURNS integer AS $$
DECLARE v_count integer; v_take integer;
BEGIN
  INSERT INTO public.mobile_send_counters (organization_id, account_id, day, count)
  VALUES (p_org, p_account, p_day, 0)
  ON CONFLICT (organization_id, account_id, day) DO NOTHING;
  SELECT count INTO v_count FROM public.mobile_send_counters
   WHERE organization_id = p_org AND account_id = p_account AND day = p_day
   FOR UPDATE;
  v_take := GREATEST(LEAST(p_n, p_cap - v_count), 0);
  UPDATE public.mobile_send_counters SET count = count + v_take
   WHERE organization_id = p_org AND account_id = p_account AND day = p_day;
  RETURN v_take;
END;
$$ LANGUAGE plpgsql SET search_path = public, pg_temp;
-- Only the mobile service (service role) may call it; not exposed to anon or signed-in users.
REVOKE ALL ON FUNCTION public.mobile_reserve_sends(text, text, date, integer, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.mobile_reserve_sends(text, text, date, integer, integer) TO service_role;

-- updated_at triggers (one function per table, as in 343).
CREATE OR REPLACE FUNCTION public.update_mobile_scheduled_actions_updated_at()
RETURNS trigger AS $$ BEGIN NEW.updated_at = now(); RETURN NEW; END; $$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS mobile_scheduled_actions_updated_at ON public.mobile_scheduled_actions;
CREATE TRIGGER mobile_scheduled_actions_updated_at BEFORE UPDATE ON public.mobile_scheduled_actions
  FOR EACH ROW EXECUTE FUNCTION public.update_mobile_scheduled_actions_updated_at();

CREATE OR REPLACE FUNCTION public.update_mobile_send_counters_updated_at()
RETURNS trigger AS $$ BEGIN NEW.updated_at = now(); RETURN NEW; END; $$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS mobile_send_counters_updated_at ON public.mobile_send_counters;
CREATE TRIGGER mobile_send_counters_updated_at BEFORE UPDATE ON public.mobile_send_counters
  FOR EACH ROW EXECUTE FUNCTION public.update_mobile_send_counters_updated_at();

-- RLS: org-scoped, as in 343. The mobile service uses the service role (bypasses RLS);
-- these keep the tables safe for any future direct surface.
ALTER TABLE public.play_messages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can view play messages for their organization" ON public.play_messages;
CREATE POLICY "Users can view play messages for their organization" ON public.play_messages
  FOR SELECT USING (organization_id = current_setting('app.current_org_id', true));
DROP POLICY IF EXISTS "Users can insert play messages for their organization" ON public.play_messages;
CREATE POLICY "Users can insert play messages for their organization" ON public.play_messages
  FOR INSERT WITH CHECK (organization_id = current_setting('app.current_org_id', true));

ALTER TABLE public.mobile_scheduled_actions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can view scheduled actions for their organization" ON public.mobile_scheduled_actions;
CREATE POLICY "Users can view scheduled actions for their organization" ON public.mobile_scheduled_actions
  FOR SELECT USING (organization_id = current_setting('app.current_org_id', true));
DROP POLICY IF EXISTS "Users can insert scheduled actions for their organization" ON public.mobile_scheduled_actions;
CREATE POLICY "Users can insert scheduled actions for their organization" ON public.mobile_scheduled_actions
  FOR INSERT WITH CHECK (organization_id = current_setting('app.current_org_id', true));
DROP POLICY IF EXISTS "Users can update scheduled actions for their organization" ON public.mobile_scheduled_actions;
CREATE POLICY "Users can update scheduled actions for their organization" ON public.mobile_scheduled_actions
  FOR UPDATE USING (organization_id = current_setting('app.current_org_id', true));

ALTER TABLE public.mobile_send_counters ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can view mobile send counters for their organization" ON public.mobile_send_counters;
CREATE POLICY "Users can view mobile send counters for their organization" ON public.mobile_send_counters
  FOR SELECT USING (organization_id = current_setting('app.current_org_id', true));
DROP POLICY IF EXISTS "Users can insert mobile send counters for their organization" ON public.mobile_send_counters;
CREATE POLICY "Users can insert mobile send counters for their organization" ON public.mobile_send_counters
  FOR INSERT WITH CHECK (organization_id = current_setting('app.current_org_id', true));
DROP POLICY IF EXISTS "Users can update mobile send counters for their organization" ON public.mobile_send_counters;
CREATE POLICY "Users can update mobile send counters for their organization" ON public.mobile_send_counters
  FOR UPDATE USING (organization_id = current_setting('app.current_org_id', true));

-- Verify (read-only): two new columns, three tables with RLS on.
SELECT table_name, column_name, data_type FROM information_schema.columns
 WHERE table_schema = 'public' AND (table_name, column_name) IN (
   ('organization', 'mobile'), ('organization', 'signup_source'))
 ORDER BY table_name, column_name;
SELECT tablename, rowsecurity FROM pg_tables
 WHERE schemaname = 'public' AND tablename IN ('play_messages', 'mobile_scheduled_actions', 'mobile_send_counters');
