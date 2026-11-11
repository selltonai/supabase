-- ============================================================
-- Migration: 432_engine-state-tables (stage: next-release/432; renumber at promotion if 432 is taken)
-- Date:      2026-11-11
-- Status:    DRAFT by lane E (the engine) for Zoran's review (card D1-7, feeds E-M1). Not applied anywhere.
-- Purpose:   What the engine keeps in files on its box today, as rows, so more than one process can share it:
--            1. engine_limits        a workspace's or a person's spend counts and limit (what organization.mobile.usage
--                                    holds today: months, days, limit_usd, the 80% warning)
--            2. engine_pacing        one mailbox's next free send turn and the turn given to each waiting row
--            3. engine_workers       each worker's heartbeat (what /health/worker reads)
--            4. engine_chat_lines    every chat line, one row each (CHATS_DIR, a JSON line each)
--            5. engine_feedback      each tester answer, one row each (FEEDBACK_PATH, a JSON line each)
-- Naming:    `chat_lines` and `feedback` on the card became engine_chat_lines and engine_feedback: public.feedback
--            already exists (the web's, release_1.0.0, other columns), and the engine_ prefix keeps all of the engine's
--            objects together (as 430).
-- Projects:  sellton-new-engine (the only reader and writer). selltonai-mobile, selltonai, selltonai-modal,
--            backoffice: none.
-- Contract:  Additive. Five new, empty tables; nothing else changes and nothing in the engine writes to them until
--            E-M1 moves its stores. Service role only: RLS on with no policies, and anon and authenticated get no
--            table privileges (as 428 and 431). Nothing here is read by the web.
-- Depends:   public.organization.
-- Rollback:  rollback/432_engine-state-tables.rollback.sql
-- Re-apply:  idempotent (IF NOT EXISTS, OR REPLACE, DROP TRIGGER IF EXISTS); a second run changes nothing.
-- ============================================================

SET LOCAL lock_timeout = '10s';

-- ---- 1. engine_limits ----------------------------------------------------------------------------------------
-- Today (service/app/spend.py): organization.mobile.usage = {"months": {"2026-10": {count_key: n}}, "days": {...},
-- "limit_usd": 50, "warned": "2026-10", "people": {user_id: {"months": {...}, "limit_usd": 30, "warned": "2026-10"}}}.
-- One row per (workspace, person or the workspace itself, kind, period):
--   kind 'month' / 'day'  period '2026-10' / '2026-10-31' (UTC); counts = {count_key: n}, the units spend.py counts
--   kind 'limit'          period ''; limit_usd = the limit (NULL: none set), warned_month = the month the 80% line was
--                         last said ('2026-10'), so it is said once a month
-- user_id '' is the workspace's own (a primary key cannot hold NULL). Days exist for the workspace only (S410).
-- The per-minute request windows (limits.py) stay in the process's memory and are NOT kept here: they live a minute.
CREATE TABLE IF NOT EXISTS public.engine_limits (
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  user_id text NOT NULL DEFAULT '',
  kind text NOT NULL CHECK (kind IN ('month', 'day', 'limit')),
  period text NOT NULL DEFAULT '',
  counts jsonb NOT NULL DEFAULT '{}'::jsonb,
  limit_usd numeric CHECK (limit_usd IS NULL OR limit_usd >= 0),
  warned_month text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (organization_id, user_id, kind, period),
  CHECK ((kind = 'limit') = (period = ''))
);

-- ---- 2. engine_pacing ----------------------------------------------------------------------------------------
-- Today (mail/pacing.py): one JSON file per mailbox, {"next": iso|null, "rows": {row_id: turn_iso}}, keyed by the
-- workspace and the mailbox's account. next_at = the next free turn; turns = the turn each waiting row was given.
CREATE TABLE IF NOT EXISTS public.engine_pacing (
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  account_id text NOT NULL,
  next_at timestamptz,
  turns jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (organization_id, account_id)
);

-- ---- 3. engine_workers ---------------------------------------------------------------------------------------
-- Today (monitoring.py): one JSON file per worker ("worker", "worker-2"), written after every tick:
-- {"at", "mode", "ticks", "dead_letters", "failing", "load"}. Not a workspace's: no organization_id. The row's own
-- updated_at is the beat's time ("at"); the service calls a worker stale after 180 seconds.
CREATE TABLE IF NOT EXISTS public.engine_workers (
  name text PRIMARY KEY,
  mode text CHECK (mode IN ('scheduler', 'idle')),
  ticks integer NOT NULL DEFAULT 0 CHECK (ticks >= 0),
  dead_letters integer NOT NULL DEFAULT 0 CHECK (dead_letters >= 0),
  failing boolean NOT NULL DEFAULT false,
  load jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- ---- 4. engine_chat_lines ------------------------------------------------------------------------------------
-- Today (chats.py): one JSON line per chat line in CHATS_DIR/<month>.jsonl: at, org_id, user_id, name, build, lang,
-- where, play_id, play_name, role, text, card (the card's kind only), about. created_at is the line's "at".
-- No foreign key on play_id: a deleted play's lines stay (S161). Appended and read, erased only for someone who asks
-- not to be emailed (S136), and pruned past 12 months, so those are deletes by the engine, never updates.
CREATE TABLE IF NOT EXISTS public.engine_chat_lines (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  user_id text,
  user_name text,        -- the person's own sign-off name ("name")
  app_build text,        -- "build" (X-App-Build)
  lang text,
  place text NOT NULL,   -- "where": home, play or person
  play_id text,
  play_name text,
  role text,
  body text,             -- "text"
  card_kind text,        -- "card"
  about text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_engine_chat_lines_org_user_at ON public.engine_chat_lines (organization_id, user_id, created_at);
CREATE INDEX IF NOT EXISTS idx_engine_chat_lines_org_play_at ON public.engine_chat_lines (organization_id, play_id, created_at);

-- ---- 5. engine_feedback --------------------------------------------------------------------------------------
-- Today (feedback.py): one JSON line per answer in FEEDBACK_PATH: at, org_id, user_id, name, build, lang, where,
-- play_id, play_name, text. created_at is the answer's "at"; last_at(org, user) reads the newest per person.
CREATE TABLE IF NOT EXISTS public.engine_feedback (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  user_id text NOT NULL,
  user_name text,
  app_build text,
  lang text,
  place text,            -- "where"
  play_id text,
  play_name text,
  body text NOT NULL,    -- "text"
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_engine_feedback_org_user_at ON public.engine_feedback (organization_id, user_id, created_at DESC);

-- updated_at: one shared function, a trigger on each table.
CREATE OR REPLACE FUNCTION public.engine_set_updated_at()
RETURNS trigger AS $$ BEGIN NEW.updated_at = now(); RETURN NEW; END; $$ LANGUAGE plpgsql SET search_path = public, pg_temp;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['engine_limits', 'engine_pacing', 'engine_workers', 'engine_chat_lines', 'engine_feedback'] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I', t || '_updated_at', t);
    EXECUTE format('CREATE TRIGGER %I BEFORE UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.engine_set_updated_at()',
                   t || '_updated_at', t);
    -- Access: the service role only (as 428 and 431). RLS on with no policies, on purpose.
    EXECUTE format('REVOKE ALL ON TABLE public.%I FROM PUBLIC, anon, authenticated', t);
    EXECUTE format('GRANT ALL ON TABLE public.%I TO service_role', t);
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
  END LOOP;
END $$;
REVOKE ALL ON FUNCTION public.engine_set_updated_at() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.engine_set_updated_at() TO service_role;
REVOKE ALL ON SEQUENCE public.engine_chat_lines_id_seq, public.engine_feedback_id_seq FROM PUBLIC, anon, authenticated;
GRANT ALL ON SEQUENCE public.engine_chat_lines_id_seq, public.engine_feedback_id_seq TO service_role;

COMMENT ON TABLE public.engine_limits IS 'The engine''s spend counts and limits per workspace and person (replaces organization.mobile.usage for the engine). Service role only.';
COMMENT ON TABLE public.engine_pacing IS 'One mailbox''s next free send turn and the turns given to waiting rows. Service role only.';
COMMENT ON TABLE public.engine_workers IS 'Each engine worker''s heartbeat, read by /health/worker. Service role only.';
COMMENT ON TABLE public.engine_chat_lines IS 'Every chat line, per person, kept for improving Sellton (never read by the web). Service role only.';
COMMENT ON TABLE public.engine_feedback IS 'Tester answers to "How is Sellton working for you?". Service role only.';

-- Verify (read-only): five tables with RLS on.
SELECT tablename, rowsecurity FROM pg_tables
 WHERE schemaname = 'public'
   AND tablename IN ('engine_limits', 'engine_pacing', 'engine_workers', 'engine_chat_lines', 'engine_feedback');
