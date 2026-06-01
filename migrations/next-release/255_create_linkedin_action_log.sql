-- ============================================================
--  Migration: 243_create_linkedin_action_log
--  Date:      2026-04-28
--  Author:    Sellton AI — LinkedIn integration Phase 2 (slice 1)
--  Plan ref:  /Ground Truth/LINKEDIN_INTEGRATION_PLAN_V2.md  §3.2 + §5
--  Depends:   240_create_linkedin_accounts.sql (linkedin_accounts must exist)
-- ============================================================
--
--  Purpose
--  -------
--  Audit + rate-limit primitive. One row per outbound Unipile action we
--  trigger (invitation send, message send, …). Phase 2 uses it for two
--  things:
--
--    1. Rate limiting — `SELECT count(*) WHERE account_id=X AND created_at >
--       now() - interval '24 hours' AND action_type='invitation'` is the
--       cheap query that gates the next send.
--    2. Forensics — every Unipile call we make is observable from SQL,
--       independent of Modal/Vercel logs that have shorter retention.
--
--  Numbering
--  ---------
--  Plan §3.2 reserves 243 for this table. We're skipping ahead from 240
--  because Phase 2 of the integration doesn't need 241 (campaign_emails
--  rename) or 242 (campaign_contacts) — those land with Phase 1's sequence
--  engine. This table only references linkedin_accounts so order is
--  independent: applying 243 before 241/242 is safe.
--
--  Idempotency
--  -----------
--  Fully re-runnable. CREATE ... IF NOT EXISTS / DROP POLICY IF EXISTS
--  patterns. NOTIFY pgrst at the end so PostgREST picks up the new table
--  immediately (PGRST204 trap).
--
--  Apply
--  -----
--    (a) Supabase Studio SQL editor → paste this file → Run.
--    (b) psql "$SUPABASE_DEV_URL" -f 243_create_linkedin_action_log.sql
--
--  Verify (after apply)
--  --------------------
--    SELECT * FROM linkedin_action_log LIMIT 0;                         -- columns load
--    SELECT relrowsecurity FROM pg_class WHERE relname='linkedin_action_log';  -- t
--    SELECT count(*) FROM pg_indexes WHERE tablename='linkedin_action_log';    -- 3
--
--  Rollback (safe while empty)
--  ---------------------------
--    DROP TABLE IF EXISTS public.linkedin_action_log CASCADE;
-- ============================================================


-- ============================================================
--  TABLE: public.linkedin_action_log
-- ============================================================

CREATE TABLE IF NOT EXISTS public.linkedin_action_log (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Multi-tenant scoping. Mirrors linkedin_accounts; both stay TEXT to
  -- match Sellton's Clerk-id convention.
  organization_id     TEXT NOT NULL,
  user_id             TEXT NOT NULL,

  -- The Sellton-side LinkedIn account row this action ran from. ON DELETE
  -- CASCADE: if the user disconnects (deletes the row in linkedin_accounts)
  -- the audit log goes with it. We don't keep history past disconnect at
  -- this stage; if compliance ever requires retention, switch to SET NULL
  -- and migrate.
  linkedin_account_id UUID NOT NULL
                      REFERENCES public.linkedin_accounts(id)
                      ON DELETE CASCADE,

  -- Unipile's account identifier — denormalized so we can rate-limit even
  -- if linkedin_account_id is later soft-deleted. The (account_id, action_type,
  -- created_at) tuple is the rate-limit query key.
  unipile_account_id  TEXT NOT NULL,

  -- What kind of Unipile call this was. Open-ended so future channels can
  -- reuse the table; CHECK constraint enumerates current values.
  action_type         TEXT NOT NULL
                      CHECK (action_type IN (
                        'invitation',
                        'message',
                        'comment',
                        'profile_view',
                        'post'
                      )),

  -- Who/what we acted on. provider_id is Unipile's stable handle for the
  -- recipient — that's what the send call took. recipient_url is the
  -- LinkedIn vanity URL when known, kept for human-readable forensics.
  recipient_provider_id TEXT,
  recipient_url         TEXT,

  -- Outcome. success=true when Unipile returned a non-error response.
  -- error_code captures Unipile's structured error (e.g. 'rate_limit',
  -- 'invalid_account') for triage; error_message is the free-text fallback.
  success             BOOLEAN NOT NULL,
  error_code          TEXT,
  error_message       TEXT,

  -- Optional payload snapshots for debugging. Don't put large bodies here;
  -- truncate at the application layer.
  request_payload     JSONB,
  response_payload    JSONB,

  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- ============================================================
--  INDEXES — built around the rate-limit query
-- ============================================================

-- Daily count by account+action: the hot path for rate limiting.
-- BRIN-on-created_at would be tempting but the table will be small;
-- standard btree composite is the right call.
CREATE INDEX IF NOT EXISTS idx_linkedin_action_log_account_window
  ON public.linkedin_action_log(unipile_account_id, action_type, created_at DESC);

-- Org-wide queries (admin dashboards, billing reports).
CREATE INDEX IF NOT EXISTS idx_linkedin_action_log_org_created
  ON public.linkedin_action_log(organization_id, created_at DESC);

-- Failures-only filter for monitoring dashboards.
CREATE INDEX IF NOT EXISTS idx_linkedin_action_log_failures
  ON public.linkedin_action_log(unipile_account_id, created_at DESC)
  WHERE success = FALSE;


-- ============================================================
--  RLS — same shape as linkedin_accounts
-- ============================================================
--
-- Service role (BFF) bypasses RLS; these policies are defense in depth
-- for the unlikely case an authenticated client touches the table directly.
-- Policy claims match linkedin_accounts: auth.jwt()->>'org_id' / 'sub'.

ALTER TABLE public.linkedin_action_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS linkedin_action_log_org_select ON public.linkedin_action_log;

-- SELECT — anyone in the org can read action history. INSERT/UPDATE/DELETE
-- intentionally not granted to authenticated users: the audit log is
-- append-only and BFF-managed.
CREATE POLICY linkedin_action_log_org_select
  ON public.linkedin_action_log
  FOR SELECT
  TO authenticated
  USING (organization_id = (auth.jwt() ->> 'org_id'));


-- ============================================================
--  COMMENTS
-- ============================================================

COMMENT ON TABLE public.linkedin_action_log IS
  'Append-only audit + rate-limit ledger for outbound Unipile actions. One row per send attempt regardless of success. Forensics survive Modal/Vercel log retention windows.';

COMMENT ON COLUMN public.linkedin_action_log.unipile_account_id IS
  'Denormalized from linkedin_accounts.unipile_account_id so rate-limit queries don''t need a join. Stays valid even if the parent row is later disconnected.';

COMMENT ON COLUMN public.linkedin_action_log.action_type IS
  'Phase 2: invitation, message. Phase 3+: comment, profile_view, post. Adding a value requires a migration.';

COMMENT ON COLUMN public.linkedin_action_log.success IS
  'TRUE if Unipile returned a non-error response. Does NOT indicate the recipient saw or accepted the action — those events arrive via webhooks and update separate tables.';


-- ============================================================
--  PostgREST schema-cache reload
-- ============================================================
NOTIFY pgrst, 'reload schema';
