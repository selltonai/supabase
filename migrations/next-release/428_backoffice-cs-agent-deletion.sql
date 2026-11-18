-- ============================================================
-- Migration: 428_backoffice-cs-agent-deletion (stage: next-release/428; renumber at promotion if 428 is taken)
-- Date:      2026-11-11
-- Purpose:   The backoffice's customer-success agent, workspace archive and delete: one job row per request, which
--            every system drains for its own part, and which stays as the receipt.
--            1. workspace_deletions: who asked, why, the mode (archive | delete), the dry-run inventory, the
--               systems that take part, one claim and one receipt per system, the earliest purge time (24 hours
--               after the request) and the outcome. At most one open request per organization.
-- Projects:  selltonai-database/supabase (owner). backoffice writes the row and does its own parts.
--            selltonai-modal, the mobile service, the vector service and the gmail-api service: each may claim and
--            write its own part's columns in its own release; until then their parts stay unclaimed. selltonai and
--            the engine: none.
-- Contract:  Additive. One new table; no other object changes. Service role only: RLS on with no policies, and anon
--            and authenticated get no table privileges.
--            organization_id is plain text with no foreign key, so the row outlives the organization it removed.
--            Parts: supabase, pinecone, mongo, gmail_api, unipile, mobile, stripe, clerk. A request lists the parts
--            that apply in systems; a service claims only a listed part, by setting <part>_claimed_at and
--            <part>_claimed_by where both are NULL (or the claim is stale), then writes <part>_receipt, a jsonb
--            object with status 'done', 'failed' or 'skipped' plus its counts and times. Each part has its own
--            columns, so two services never overwrite each other's receipt. In delete mode no part is claimed
--            before purge_not_before. The row is completed only when every listed part has a receipt with status
--            done or skipped; it runs (or completes, fails, reverses) only once confirmed_at is set.
--            The backoffice treats a missing table as "feature not deployed", so this file and the backoffice build
--            can ship in either order. Application code: none must ship together with this file.
-- Depends:   public.update_updated_at_column() (release_1.0.0; last re-declared by 300). No foreign key to
--            public.organization, on purpose (above).
-- Rollback:  rollback/428_backoffice-cs-agent-deletion.rollback.sql
--
-- Definitions:
--   Open       status pending, running or failed: a failed part stays open until a person resolves it (re-runs the
--              part, or cancels the request).
--   Actor      requested_by, cancelled_by, reversed_by: the staff user's sign-in email. <part>_claimed_by: the service
--              or worker that claimed the part.
-- ============================================================

SET LOCAL lock_timeout = '10s';

CREATE TABLE IF NOT EXISTS public.workspace_deletions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  -- The organization's id as it was. No foreign key: the row is the receipt and must outlive the organization.
  organization_id text NOT NULL CHECK (char_length(organization_id) BETWEEN 1 AND 200),
  -- The name as it was when the request was confirmed (the name typed to confirm).
  organization_name text CHECK (organization_name IS NULL OR char_length(organization_name) <= 300),
  mode text NOT NULL CHECK (mode IN ('archive', 'delete')),
  requested_by text NOT NULL CHECK (char_length(requested_by) BETWEEN 1 AND 320),
  reason text NOT NULL CHECK (char_length(reason) BETWEEN 1 AND 2000),
  requested_at timestamptz NOT NULL DEFAULT now(),
  -- The second step: the name typed and confirmed.
  confirmed_at timestamptz,
  -- A workspace with an open invoice goes ahead only with an explicit override and its reason.
  open_invoice_override boolean NOT NULL DEFAULT false,
  override_reason text CHECK (override_reason IS NULL OR char_length(override_reason) BETWEEN 1 AND 2000),
  -- What exists where, from the dry run.
  inventory jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(inventory) = 'object'),
  -- The parts that apply to this request.
  systems text[] NOT NULL DEFAULT '{}'::text[]
    CHECK (systems <@ ARRAY['supabase', 'pinecone', 'mongo', 'gmail_api', 'unipile', 'mobile', 'stripe', 'clerk']::text[]),
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'running', 'completed', 'failed', 'cancelled', 'reversed')),
  -- The purge never starts before this (delete mode).
  purge_not_before timestamptz NOT NULL DEFAULT (now() + interval '24 hours'),
  -- One claim and one receipt per part.
  supabase_claimed_at timestamptz,
  supabase_claimed_by text,
  supabase_receipt jsonb,
  pinecone_claimed_at timestamptz,
  pinecone_claimed_by text,
  pinecone_receipt jsonb,
  mongo_claimed_at timestamptz,
  mongo_claimed_by text,
  mongo_receipt jsonb,
  gmail_api_claimed_at timestamptz,
  gmail_api_claimed_by text,
  gmail_api_receipt jsonb,
  unipile_claimed_at timestamptz,
  unipile_claimed_by text,
  unipile_receipt jsonb,
  mobile_claimed_at timestamptz,
  mobile_claimed_by text,
  mobile_receipt jsonb,
  stripe_claimed_at timestamptz,
  stripe_claimed_by text,
  stripe_receipt jsonb,
  clerk_claimed_at timestamptz,
  clerk_claimed_by text,
  clerk_receipt jsonb,
  completed_at timestamptz,
  cancelled_by text,
  cancelled_at timestamptz,
  -- An archive undone within its retention window.
  reversed_by text,
  reversed_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT workspace_deletions_delay_check CHECK (purge_not_before >= requested_at + interval '24 hours'),
  CONSTRAINT workspace_deletions_override_check CHECK (NOT open_invoice_override OR override_reason IS NOT NULL),
  CONSTRAINT workspace_deletions_confirmed_check CHECK (
    status IN ('pending', 'cancelled') OR confirmed_at IS NOT NULL
  ),
  CONSTRAINT workspace_deletions_cancelled_check CHECK (
    status <> 'cancelled' OR (cancelled_by IS NOT NULL AND cancelled_at IS NOT NULL)
  ),
  CONSTRAINT workspace_deletions_reversed_check CHECK (
    status <> 'reversed' OR (mode = 'archive' AND reversed_by IS NOT NULL AND reversed_at IS NOT NULL)
  ),
  -- Completed only when every listed part is in, done or skipped.
  CONSTRAINT workspace_deletions_completed_check CHECK (
    status <> 'completed' OR (
      completed_at IS NOT NULL
      AND cardinality(systems) > 0
      AND (NOT ('supabase' = ANY (systems)) OR coalesce(supabase_receipt ->> 'status', '') IN ('done', 'skipped'))
      AND (NOT ('pinecone' = ANY (systems)) OR coalesce(pinecone_receipt ->> 'status', '') IN ('done', 'skipped'))
      AND (NOT ('mongo' = ANY (systems)) OR coalesce(mongo_receipt ->> 'status', '') IN ('done', 'skipped'))
      AND (NOT ('gmail_api' = ANY (systems)) OR coalesce(gmail_api_receipt ->> 'status', '') IN ('done', 'skipped'))
      AND (NOT ('unipile' = ANY (systems)) OR coalesce(unipile_receipt ->> 'status', '') IN ('done', 'skipped'))
      AND (NOT ('mobile' = ANY (systems)) OR coalesce(mobile_receipt ->> 'status', '') IN ('done', 'skipped'))
      AND (NOT ('stripe' = ANY (systems)) OR coalesce(stripe_receipt ->> 'status', '') IN ('done', 'skipped'))
      AND (NOT ('clerk' = ANY (systems)) OR coalesce(clerk_receipt ->> 'status', '') IN ('done', 'skipped'))
    )
  ),
  -- Each part: claimed with who, only when listed, not before the purge time in delete mode; a receipt only after a
  -- claim, as an object with a known status.
  CONSTRAINT workspace_deletions_supabase_part_check CHECK (
    (supabase_claimed_at IS NULL) = (supabase_claimed_by IS NULL)
    AND (supabase_claimed_at IS NULL OR 'supabase' = ANY (systems))
    AND (supabase_claimed_at IS NULL OR mode = 'archive' OR supabase_claimed_at >= purge_not_before)
    AND (supabase_receipt IS NULL OR (supabase_claimed_at IS NOT NULL AND jsonb_typeof(supabase_receipt) = 'object'
         AND coalesce(supabase_receipt ->> 'status', '') IN ('done', 'failed', 'skipped')))
  ),
  CONSTRAINT workspace_deletions_pinecone_part_check CHECK (
    (pinecone_claimed_at IS NULL) = (pinecone_claimed_by IS NULL)
    AND (pinecone_claimed_at IS NULL OR 'pinecone' = ANY (systems))
    AND (pinecone_claimed_at IS NULL OR mode = 'archive' OR pinecone_claimed_at >= purge_not_before)
    AND (pinecone_receipt IS NULL OR (pinecone_claimed_at IS NOT NULL AND jsonb_typeof(pinecone_receipt) = 'object'
         AND coalesce(pinecone_receipt ->> 'status', '') IN ('done', 'failed', 'skipped')))
  ),
  CONSTRAINT workspace_deletions_mongo_part_check CHECK (
    (mongo_claimed_at IS NULL) = (mongo_claimed_by IS NULL)
    AND (mongo_claimed_at IS NULL OR 'mongo' = ANY (systems))
    AND (mongo_claimed_at IS NULL OR mode = 'archive' OR mongo_claimed_at >= purge_not_before)
    AND (mongo_receipt IS NULL OR (mongo_claimed_at IS NOT NULL AND jsonb_typeof(mongo_receipt) = 'object'
         AND coalesce(mongo_receipt ->> 'status', '') IN ('done', 'failed', 'skipped')))
  ),
  CONSTRAINT workspace_deletions_gmail_api_part_check CHECK (
    (gmail_api_claimed_at IS NULL) = (gmail_api_claimed_by IS NULL)
    AND (gmail_api_claimed_at IS NULL OR 'gmail_api' = ANY (systems))
    AND (gmail_api_claimed_at IS NULL OR mode = 'archive' OR gmail_api_claimed_at >= purge_not_before)
    AND (gmail_api_receipt IS NULL OR (gmail_api_claimed_at IS NOT NULL AND jsonb_typeof(gmail_api_receipt) = 'object'
         AND coalesce(gmail_api_receipt ->> 'status', '') IN ('done', 'failed', 'skipped')))
  ),
  CONSTRAINT workspace_deletions_unipile_part_check CHECK (
    (unipile_claimed_at IS NULL) = (unipile_claimed_by IS NULL)
    AND (unipile_claimed_at IS NULL OR 'unipile' = ANY (systems))
    AND (unipile_claimed_at IS NULL OR mode = 'archive' OR unipile_claimed_at >= purge_not_before)
    AND (unipile_receipt IS NULL OR (unipile_claimed_at IS NOT NULL AND jsonb_typeof(unipile_receipt) = 'object'
         AND coalesce(unipile_receipt ->> 'status', '') IN ('done', 'failed', 'skipped')))
  ),
  CONSTRAINT workspace_deletions_mobile_part_check CHECK (
    (mobile_claimed_at IS NULL) = (mobile_claimed_by IS NULL)
    AND (mobile_claimed_at IS NULL OR 'mobile' = ANY (systems))
    AND (mobile_claimed_at IS NULL OR mode = 'archive' OR mobile_claimed_at >= purge_not_before)
    AND (mobile_receipt IS NULL OR (mobile_claimed_at IS NOT NULL AND jsonb_typeof(mobile_receipt) = 'object'
         AND coalesce(mobile_receipt ->> 'status', '') IN ('done', 'failed', 'skipped')))
  ),
  CONSTRAINT workspace_deletions_stripe_part_check CHECK (
    (stripe_claimed_at IS NULL) = (stripe_claimed_by IS NULL)
    AND (stripe_claimed_at IS NULL OR 'stripe' = ANY (systems))
    AND (stripe_claimed_at IS NULL OR mode = 'archive' OR stripe_claimed_at >= purge_not_before)
    AND (stripe_receipt IS NULL OR (stripe_claimed_at IS NOT NULL AND jsonb_typeof(stripe_receipt) = 'object'
         AND coalesce(stripe_receipt ->> 'status', '') IN ('done', 'failed', 'skipped')))
  ),
  CONSTRAINT workspace_deletions_clerk_part_check CHECK (
    (clerk_claimed_at IS NULL) = (clerk_claimed_by IS NULL)
    AND (clerk_claimed_at IS NULL OR 'clerk' = ANY (systems))
    AND (clerk_claimed_at IS NULL OR mode = 'archive' OR clerk_claimed_at >= purge_not_before)
    AND (clerk_receipt IS NULL OR (clerk_claimed_at IS NOT NULL AND jsonb_typeof(clerk_receipt) = 'object'
         AND coalesce(clerk_receipt ->> 'status', '') IN ('done', 'failed', 'skipped')))
  )
);

-- One open request per organization.
CREATE UNIQUE INDEX IF NOT EXISTS workspace_deletions_one_open_unique
  ON public.workspace_deletions (organization_id)
  WHERE status IN ('pending', 'running', 'failed');
CREATE INDEX IF NOT EXISTS workspace_deletions_queue_idx
  ON public.workspace_deletions (status, purge_not_before)
  WHERE status IN ('pending', 'running', 'failed');
CREATE INDEX IF NOT EXISTS workspace_deletions_org_idx
  ON public.workspace_deletions (organization_id, requested_at DESC);

DROP TRIGGER IF EXISTS update_workspace_deletions_updated_at ON public.workspace_deletions;
CREATE TRIGGER update_workspace_deletions_updated_at
  BEFORE UPDATE ON public.workspace_deletions
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

-- Access: the service role only ----------------------------------------------------------------------
-- Supabase grants new tables to anon and authenticated by default; take that away. RLS is on with no policies on
-- purpose: the backoffice and the services that drain the job use the service role, and browser keys see nothing.

REVOKE ALL ON TABLE public.workspace_deletions FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.workspace_deletions TO service_role;
ALTER TABLE public.workspace_deletions ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.workspace_deletions IS
  'Backoffice customer-success agent: a workspace archive or delete request and its receipt. organization_id has no foreign key, so the row outlives the organization. systems lists the parts that apply; each part has <part>_claimed_at, <part>_claimed_by and <part>_receipt (an object with status done, failed or skipped). In delete mode no part is claimed before purge_not_before; the row completes only when every listed part is done or skipped. At most one open request (pending, running, failed) per organization. Service role only.';

-- Fail the file if a browser key can still reach the table.
DO $$
BEGIN
  IF has_table_privilege('anon', 'public.workspace_deletions', 'SELECT')
     OR has_table_privilege('authenticated', 'public.workspace_deletions', 'SELECT')
     OR has_table_privilege('anon', 'public.workspace_deletions', 'INSERT')
     OR has_table_privilege('authenticated', 'public.workspace_deletions', 'INSERT')
     OR has_table_privilege('anon', 'public.workspace_deletions', 'UPDATE')
     OR has_table_privilege('authenticated', 'public.workspace_deletions', 'UPDATE')
     OR has_table_privilege('anon', 'public.workspace_deletions', 'DELETE')
     OR has_table_privilege('authenticated', 'public.workspace_deletions', 'DELETE') THEN
    RAISE EXCEPTION '428: anon or authenticated can still read or write workspace_deletions';
  END IF;
END $$;

-- Verify (read-only):
-- select relrowsecurity from pg_class where oid = 'public.workspace_deletions'::regclass;          -- true
-- select has_table_privilege('anon', 'public.workspace_deletions', 'SELECT'),                     -- false
--        has_table_privilege('service_role', 'public.workspace_deletions', 'INSERT');             -- true
-- select count(*) from pg_constraint where conrelid = 'public.workspace_deletions'::regclass
--    and contype = 'f';                                                                           -- 0
