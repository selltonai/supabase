-- ============================================================
-- Migration: 422_backoffice-cs-agent-core (stage: next-release/422; renumber at promotion if 422 is taken)
-- Date:      2026-11-11
-- Purpose:   The backoffice's customer-success agent, its own tables (core). Staff ask it what is happening in
--            the workspaces, it writes a morning brief, and it proposes actions that a person approves.
--            1. cs_threads, cs_messages: the staff chat with the agent. A thread belongs to one staff user and,
--               optionally, to one workspace.
--            2. cs_briefs: one row per day and scope (all workspaces, or one), as the morning job wrote it.
--            3. cs_recommendations: everything the agent or a staff user proposes for a workspace (an email, a
--               credit, a trial, a note to follow up), its approval, its execution and its outcome. A row cannot
--               be approved, executed or failed without a recorded approver (the check below).
--            4. cs_costs: what the backoffice's own model and data calls cost, one row per call. Never the
--               customers' ledger: nothing here is invoiced, and the backoffice writes no row to public.usage.
--            5. email_sequence_steps: two more audience modes (chase, segment) and an optional signup_source
--               filter (web | mobile), so a step can be kept to workspaces created on the web or on the phone.
-- Projects:  selltonai-database/supabase (owner). backoffice is the only reader and writer of all of it.
--            selltonai, selltonai-modal, the mobile service and the engine: none; no page, cron or queue of
--            theirs reads these objects.
-- Contract:  Additive. Five new tables, one widened CHECK and one nullable column on a backoffice-owned table.
--            No existing row changes; existing email_sequence_steps rows keep their audience_mode and get
--            signup_source NULL (no filter, as today). Service role only: RLS on with no policies, and anon and
--            authenticated get no table privileges. The backoffice treats a missing table or column as "feature
--            not deployed", so this file and the backoffice build can ship in either order.
--            Application code: none must ship together with this file.
-- Depends:   public.organization, public.email_sequence_steps (340, 344),
--            public.update_updated_at_column() (release_1.0.0; last re-declared by 300).
-- Rollback:  rollback/422_backoffice-cs-agent-core.rollback.sql
-- ============================================================

-- organization is read on every request; fail fast instead of queueing behind a long transaction (the runner rolls
-- the file back and it can be re-run).
SET LOCAL lock_timeout = '10s';

-- 1. The staff chat ---------------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.cs_threads (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  -- The backoffice staff user (their sign-in email). Staff users live in the backoffice's own store, so no key.
  staff_user text NOT NULL CHECK (char_length(staff_user) BETWEEN 1 AND 320),
  -- NULL: a thread about all workspaces. Set: a thread about this workspace only.
  organization_id text REFERENCES public.organization(id) ON DELETE CASCADE,
  title text CHECK (title IS NULL OR char_length(title) <= 200),
  archived_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS cs_threads_staff_recent_idx
  ON public.cs_threads (staff_user, updated_at DESC);
CREATE INDEX IF NOT EXISTS cs_threads_org_recent_idx
  ON public.cs_threads (organization_id, updated_at DESC)
  WHERE organization_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.cs_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  thread_id uuid NOT NULL REFERENCES public.cs_threads(id) ON DELETE CASCADE,
  role text NOT NULL CHECK (role IN ('user', 'assistant', 'tool')),
  content text,
  -- What the agent read to answer: the reads it ran and a short result of each. Shown folded under the answer.
  trace jsonb NOT NULL DEFAULT '[]'::jsonb,
  -- The proposals this message created (cs_recommendations.id).
  recommendation_ids uuid[] NOT NULL DEFAULT '{}'::uuid[],
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS cs_messages_thread_idx
  ON public.cs_messages (thread_id, created_at);

-- 2. The morning brief ------------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.cs_briefs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  day date NOT NULL,
  -- 'global' for the brief over all workspaces, else the workspace's id. One row per day and scope: a second run of
  -- the morning job on the same day updates the row, it never adds one.
  scope_key text NOT NULL,
  organization_id text REFERENCES public.organization(id) ON DELETE CASCADE,
  segment text,
  previous_segment text,
  brief jsonb NOT NULL DEFAULT '{}'::jsonb,
  -- false: written from the numbers alone; true: a model wrote the words.
  model_used boolean NOT NULL DEFAULT false,
  slack_posted_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT cs_briefs_day_scope_unique UNIQUE (day, scope_key),
  CONSTRAINT cs_briefs_scope_check CHECK (
    (scope_key = 'global' AND organization_id IS NULL)
    OR (organization_id IS NOT NULL AND scope_key = organization_id)
  )
);

CREATE INDEX IF NOT EXISTS cs_briefs_org_day_idx
  ON public.cs_briefs (organization_id, day DESC)
  WHERE organization_id IS NOT NULL;

-- 3. Proposals, their approval and their outcome ----------------------------------------------------

CREATE TABLE IF NOT EXISTS public.cs_recommendations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  -- What is proposed: email, tip, play, credit, allowance, trial, discount, update, note. The backoffice validates
  -- the value; it is free text here so a new kind needs no migration.
  kind text NOT NULL CHECK (char_length(kind) BETWEEN 1 AND 40),
  status text NOT NULL DEFAULT 'proposed'
    CHECK (status IN ('proposed', 'approved', 'executed', 'dismissed', 'expired', 'failed')),
  title text CHECK (title IS NULL OR char_length(title) <= 300),
  -- The thing itself (an email's subject and body, a trial's days and credit), by kind.
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  -- The facts the proposal rests on, as the agent read them.
  grounding jsonb NOT NULL DEFAULT '{}'::jsonb,
  reason text CHECK (reason IS NULL OR char_length(reason) <= 2000),
  -- 'agent', or the staff user who wrote it by hand.
  created_by text NOT NULL DEFAULT 'agent',
  thread_id uuid REFERENCES public.cs_threads(id) ON DELETE SET NULL,
  -- Proposals approved and measured as one (the same offer to a group of workspaces).
  batch_id uuid,
  -- Set by the writer to make a proposal single: one per workspace, kind and period. NULL: no such rule.
  dedupe_key text CHECK (dedupe_key IS NULL OR char_length(dedupe_key) <= 300),
  approved_by text,
  approved_at timestamptz,
  executed_at timestamptz,
  dismissed_by text,
  dismissed_at timestamptz,
  expires_at timestamptz,
  -- Execution: a run claims the row; another run skips it until the claim is 10 minutes old (a crash).
  claimed_at timestamptz,
  attempts integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  last_error text,
  -- What came of it (opened, replied, activated, seats added), filled later.
  outcome jsonb NOT NULL DEFAULT '{}'::jsonb,
  outcome_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  -- Nothing is approved, executed or failed without a recorded approver and time.
  CONSTRAINT cs_recommendations_approval_check CHECK (
    status NOT IN ('approved', 'executed', 'failed')
    OR (approved_by IS NOT NULL AND approved_at IS NOT NULL)
  ),
  CONSTRAINT cs_recommendations_executed_check CHECK (status <> 'executed' OR executed_at IS NOT NULL)
);

CREATE UNIQUE INDEX IF NOT EXISTS cs_recommendations_dedupe_unique
  ON public.cs_recommendations (dedupe_key)
  WHERE dedupe_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS cs_recommendations_status_idx
  ON public.cs_recommendations (status, created_at DESC);
CREATE INDEX IF NOT EXISTS cs_recommendations_org_idx
  ON public.cs_recommendations (organization_id, created_at DESC);
CREATE INDEX IF NOT EXISTS cs_recommendations_batch_idx
  ON public.cs_recommendations (batch_id)
  WHERE batch_id IS NOT NULL;

-- 4. The backoffice's own costs ----------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.cs_costs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at timestamptz NOT NULL DEFAULT now(),
  -- What the call was for: brief, chat, draft, classify_reply, company_profile, signals.
  task_kind text NOT NULL CHECK (char_length(task_kind) BETWEEN 1 AND 60),
  provider text NOT NULL CHECK (char_length(provider) BETWEEN 1 AND 60),
  model text,
  -- The workspace the call was about, when there was one. The cost stays when the workspace is deleted.
  organization_id text REFERENCES public.organization(id) ON DELETE SET NULL,
  thread_id uuid,
  input_tokens integer NOT NULL DEFAULT 0 CHECK (input_tokens >= 0),
  output_tokens integer NOT NULL DEFAULT 0 CHECK (output_tokens >= 0),
  units numeric(12, 3) NOT NULL DEFAULT 0 CHECK (units >= 0),
  usd numeric(12, 6) NOT NULL DEFAULT 0 CHECK (usd >= 0),
  -- true: the first provider failed the task and this is the second one's call.
  fallback boolean NOT NULL DEFAULT false,
  latency_ms integer CHECK (latency_ms IS NULL OR latency_ms >= 0),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS cs_costs_created_idx
  ON public.cs_costs (created_at DESC);
CREATE INDEX IF NOT EXISTS cs_costs_task_created_idx
  ON public.cs_costs (task_kind, created_at DESC);
CREATE INDEX IF NOT EXISTS cs_costs_org_created_idx
  ON public.cs_costs (organization_id, created_at DESC)
  WHERE organization_id IS NOT NULL;

-- updated_at ---------------------------------------------------------------------------------------

DROP TRIGGER IF EXISTS update_cs_threads_updated_at ON public.cs_threads;
CREATE TRIGGER update_cs_threads_updated_at
  BEFORE UPDATE ON public.cs_threads
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_cs_briefs_updated_at ON public.cs_briefs;
CREATE TRIGGER update_cs_briefs_updated_at
  BEFORE UPDATE ON public.cs_briefs
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS update_cs_recommendations_updated_at ON public.cs_recommendations;
CREATE TRIGGER update_cs_recommendations_updated_at
  BEFORE UPDATE ON public.cs_recommendations
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

-- Access: the service role only ----------------------------------------------------------------------
-- Supabase grants new tables to anon and authenticated by default; take that away. RLS is on with no policies on
-- purpose: the backoffice reads and writes with the service role, and browser keys see nothing.

REVOKE ALL ON TABLE public.cs_threads, public.cs_messages, public.cs_briefs, public.cs_recommendations, public.cs_costs
  FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.cs_threads, public.cs_messages, public.cs_briefs, public.cs_recommendations, public.cs_costs
  TO service_role;

ALTER TABLE public.cs_threads ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cs_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cs_briefs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cs_recommendations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cs_costs ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.cs_threads IS
  'Backoffice customer-success agent: a staff user''s chat thread, about all workspaces (organization_id NULL) or one. Backoffice only.';
COMMENT ON TABLE public.cs_messages IS
  'Backoffice customer-success agent: the messages of a thread, with what the agent read to answer (trace). Backoffice only.';
COMMENT ON TABLE public.cs_briefs IS
  'Backoffice customer-success agent: the morning brief, one row per day and scope (''global'' or a workspace). Backoffice only.';
COMMENT ON TABLE public.cs_recommendations IS
  'Backoffice customer-success agent: what the agent or a staff user proposes for a workspace, its approval, execution and outcome. A row is approved, executed or failed only with approved_by and approved_at set. Backoffice only.';
COMMENT ON TABLE public.cs_costs IS
  'Backoffice customer-success agent: the backoffice''s own model and data spend, one row per call. Not the customers'' ledger (public.usage): nothing here is invoiced. Backoffice only.';

-- 5. Lifecycle email steps: two more audiences and a signup-source filter ------------------------------

ALTER TABLE public.email_sequence_steps
  DROP CONSTRAINT IF EXISTS email_sequence_steps_audience_mode_check;
ALTER TABLE public.email_sequence_steps
  ADD CONSTRAINT email_sequence_steps_audience_mode_check
  CHECK (audience_mode IN ('not_activated', 'funnel_stage', 'chase', 'segment'));

ALTER TABLE public.email_sequence_steps
  ADD COLUMN IF NOT EXISTS signup_source text;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'email_sequence_steps_signup_source_check'
      AND conrelid = 'public.email_sequence_steps'::regclass
  ) THEN
    ALTER TABLE public.email_sequence_steps
      ADD CONSTRAINT email_sequence_steps_signup_source_check
      CHECK (signup_source IS NULL OR signup_source IN ('web', 'mobile'));
  END IF;
END $$;

COMMENT ON COLUMN public.email_sequence_steps.audience_mode IS
  'not_activated: all orgs without activation/card, gated by org age >= delay. funnel_stage: legacy find_funnel_dropouts targeting. chase: workspaces in a customer-success stage, each email approved as a cs_recommendations row. segment: a group of workspaces approved as one batch.';
COMMENT ON COLUMN public.email_sequence_steps.signup_source IS
  'Keeps a step to workspaces created on the web or on the phone (organization.signup_source; NULL there = web). NULL here: no filter.';

-- Fail the file if a browser key can still reach a new table.
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['cs_threads', 'cs_messages', 'cs_briefs', 'cs_recommendations', 'cs_costs'] LOOP
    IF has_table_privilege('anon', 'public.' || t, 'SELECT')
       OR has_table_privilege('authenticated', 'public.' || t, 'SELECT')
       OR has_table_privilege('anon', 'public.' || t, 'INSERT')
       OR has_table_privilege('authenticated', 'public.' || t, 'INSERT') THEN
      RAISE EXCEPTION '422: anon or authenticated can still read or write %', t;
    END IF;
  END LOOP;
END $$;

-- Verify (read-only):
-- select relname, relrowsecurity from pg_class
--  where relname in ('cs_threads', 'cs_messages', 'cs_briefs', 'cs_recommendations', 'cs_costs') order by 1;
--   -> five rows, all true
-- select has_table_privilege('anon', 'public.cs_recommendations', 'SELECT'),            -- false
--        has_table_privilege('service_role', 'public.cs_recommendations', 'INSERT');    -- true
-- select pg_get_constraintdef(oid) from pg_constraint where conname = 'email_sequence_steps_audience_mode_check';
--   -> ... ('not_activated', 'funnel_stage', 'chase', 'segment')
-- select audience_mode, signup_source, count(*) from public.email_sequence_steps group by 1, 2 order by 1, 2;
--   -> the rows as before, signup_source NULL
