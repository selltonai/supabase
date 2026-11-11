-- ============================================================
-- Migration: 430_engine-tables (stage: next-release/430; renumber at promotion if 430 is taken)
-- Date:      2026-11-11
-- Status:    DRAFT by lane E (the engine) for Zoran's review (card D1-1). Not applied anywhere.
-- Purpose:   The engine's own queue: three NEW, EMPTY objects beside the phone's mobile_* ones, as 379 made them.
--            1. engine_actions        (same columns, constraints, indexes, trigger and RLS as mobile_scheduled_actions)
--            2. engine_send_counters  (as mobile_send_counters)
--            3. engine_reserve_sends  (as mobile_reserve_sends; reads and writes engine_send_counters only)
-- Why:       One Sellton stage Supabase serves both the phone and the engine (INF-1, 2026-11-04). The engine must never
--            share the phone's queue: with one table, two workers would process one queue. So the engine gets its own
--            tables, and the mobile_* objects stay untouched until step 6 of the specification. Never a view over them.
-- Projects:  sellton-new-engine (the only writer and reader). selltonai-mobile: none (its tables are not touched).
--            selltonai, selltonai-modal, backoffice: none.
-- Contract:  Additive. No existing object changes. The tables start empty and nothing in the engine writes to them
--            until its queue store moves (E-M0 step 1/3), so applying this file changes no behaviour.
--            Application code that must ship with it: none; the engine reads the new names when its queue store moves.
-- Depends:   public.organization, public.campaigns, public.contacts (as 379).
-- Rollback:  rollback/430_engine-tables.rollback.sql
-- Re-apply:  idempotent (IF NOT EXISTS, OR REPLACE, DROP POLICY/TRIGGER IF EXISTS); a second run changes nothing.
-- ============================================================

SET LOCAL lock_timeout = '10s';

-- Every piece of later work as a row; the worker claims a row once (pending -> running).
CREATE TABLE IF NOT EXISTS public.engine_actions (
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
CREATE INDEX IF NOT EXISTS idx_engine_actions_status_due ON public.engine_actions (status, due_at);
CREATE INDEX IF NOT EXISTS idx_engine_actions_org_play ON public.engine_actions (organization_id, play_id);

-- Emails sent per mailbox per day (the day is the user's, computed by the service).
CREATE TABLE IF NOT EXISTS public.engine_send_counters (
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  account_id text NOT NULL,
  day date NOT NULL,
  count integer NOT NULL DEFAULT 0 CHECK (count >= 0),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (organization_id, account_id, day)
);

-- Reserve up to p_n sends for the day without passing p_cap; returns how many were reserved.
CREATE OR REPLACE FUNCTION public.engine_reserve_sends(
  p_org text, p_account text, p_day date, p_n integer, p_cap integer
) RETURNS integer AS $$
DECLARE v_count integer; v_take integer;
BEGIN
  INSERT INTO public.engine_send_counters (organization_id, account_id, day, count)
  VALUES (p_org, p_account, p_day, 0)
  ON CONFLICT (organization_id, account_id, day) DO NOTHING;
  SELECT count INTO v_count FROM public.engine_send_counters
   WHERE organization_id = p_org AND account_id = p_account AND day = p_day
   FOR UPDATE;
  v_take := GREATEST(LEAST(p_n, p_cap - v_count), 0);
  UPDATE public.engine_send_counters SET count = count + v_take
   WHERE organization_id = p_org AND account_id = p_account AND day = p_day;
  RETURN v_take;
END;
$$ LANGUAGE plpgsql SET search_path = public, pg_temp;
-- Only the engine (service role) may call it; not exposed to anon or signed-in users.
REVOKE ALL ON FUNCTION public.engine_reserve_sends(text, text, date, integer, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.engine_reserve_sends(text, text, date, integer, integer) TO service_role;

-- updated_at triggers (one function per table, as in 379).
CREATE OR REPLACE FUNCTION public.update_engine_actions_updated_at()
RETURNS trigger AS $$ BEGIN NEW.updated_at = now(); RETURN NEW; END; $$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS engine_actions_updated_at ON public.engine_actions;
CREATE TRIGGER engine_actions_updated_at BEFORE UPDATE ON public.engine_actions
  FOR EACH ROW EXECUTE FUNCTION public.update_engine_actions_updated_at();

CREATE OR REPLACE FUNCTION public.update_engine_send_counters_updated_at()
RETURNS trigger AS $$ BEGIN NEW.updated_at = now(); RETURN NEW; END; $$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS engine_send_counters_updated_at ON public.engine_send_counters;
CREATE TRIGGER engine_send_counters_updated_at BEFORE UPDATE ON public.engine_send_counters
  FOR EACH ROW EXECUTE FUNCTION public.update_engine_send_counters_updated_at();

-- RLS: org-scoped, exactly as 379 does for the mobile tables (policies carried, names changed). The engine uses the
-- service role (bypasses RLS); these keep the tables safe for any future direct surface.
-- NOTE for review: 379 leaves the default anon/authenticated table grants in place and relies on these policies.
-- Kept the same here on purpose ("RLS carried"); 428's stricter REVOKE style is an option if Zoran prefers.
ALTER TABLE public.engine_actions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can view engine actions for their organization" ON public.engine_actions;
CREATE POLICY "Users can view engine actions for their organization" ON public.engine_actions
  FOR SELECT USING (organization_id = current_setting('app.current_org_id', true));
DROP POLICY IF EXISTS "Users can insert engine actions for their organization" ON public.engine_actions;
CREATE POLICY "Users can insert engine actions for their organization" ON public.engine_actions
  FOR INSERT WITH CHECK (organization_id = current_setting('app.current_org_id', true));
DROP POLICY IF EXISTS "Users can update engine actions for their organization" ON public.engine_actions;
CREATE POLICY "Users can update engine actions for their organization" ON public.engine_actions
  FOR UPDATE USING (organization_id = current_setting('app.current_org_id', true));

ALTER TABLE public.engine_send_counters ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Users can view engine send counters for their organization" ON public.engine_send_counters;
CREATE POLICY "Users can view engine send counters for their organization" ON public.engine_send_counters
  FOR SELECT USING (organization_id = current_setting('app.current_org_id', true));
DROP POLICY IF EXISTS "Users can insert engine send counters for their organization" ON public.engine_send_counters;
CREATE POLICY "Users can insert engine send counters for their organization" ON public.engine_send_counters
  FOR INSERT WITH CHECK (organization_id = current_setting('app.current_org_id', true));
DROP POLICY IF EXISTS "Users can update engine send counters for their organization" ON public.engine_send_counters;
CREATE POLICY "Users can update engine send counters for their organization" ON public.engine_send_counters
  FOR UPDATE USING (organization_id = current_setting('app.current_org_id', true));

COMMENT ON TABLE public.engine_actions IS
  'The engine''s queue of later work (the engine''s own copy of the phone''s mobile_scheduled_actions; never shared with it).';
COMMENT ON TABLE public.engine_send_counters IS
  'Emails sent per mailbox per day for the engine (the phone''s own is mobile_send_counters).';

-- Verify (read-only): two tables with RLS on, the function present.
SELECT tablename, rowsecurity FROM pg_tables
 WHERE schemaname = 'public' AND tablename IN ('engine_actions', 'engine_send_counters');
SELECT proname FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = 'engine_reserve_sends';
