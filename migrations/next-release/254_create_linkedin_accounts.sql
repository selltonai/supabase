-- ============================================================
--  Migration: 240_create_linkedin_accounts
--  Date:      2026-04-23
--  Author:    Sellton AI — LinkedIn integration Phase 0 (Slice 1, commit 1)
--  Plan ref:  /Ground Truth/LINKEDIN_INTEGRATION_PLAN_V2.md  §3.2
-- ============================================================
--
--  Purpose
--  -------
--  Foundation table for the Unipile-backed multi-channel integration.
--  Each row represents one connected social/messaging account. LinkedIn is
--  the first channel; the table is designed channel-agnostic (provider
--  column) so WhatsApp, Messenger, etc. can plug in without schema change.
--
--  Architecture context (verified against linkedin.md §5.3 and
--  SELLTON_GROUND_TRUTH.md §5):
--    - Per-user, per-org. Each Sellton user connects their own Unipile
--      account via hosted-auth flow. user_profiles.linkedin_account_id
--      already exists in the schema (per ground-truth doc) and will FK to
--      this table in a follow-up migration once the schema-management
--      pattern is settled.
--    - Service role (BFF) writes/reads on behalf of the authenticated
--      user. Direct client access from authenticated Clerk users is
--      defense-in-depth via RLS policies.
--    - ARI alignment: provider + capabilities JSONB future-proof the table
--      for additional Unipile channels and per-account feature gating
--      (e.g. InMail availability) without further schema changes.
--
--  Idempotency
--  -----------
--  Fully re-runnable. CREATE ... IF NOT EXISTS / DROP ... IF EXISTS
--  patterns throughout. Trailing NOTIFY pgrst, 'reload schema' so
--  PostgREST picks up the new table immediately (lesson from this
--  session's PGRST204 schema-cache trap).
--
--  Apply
--  -----
--  Dev only at slice-1 stage. Two paths:
--    (a) Supabase Studio SQL editor → paste this file → Run.
--    (b) psql "$SUPABASE_DEV_URL" -f 240_create_linkedin_accounts.sql
--
--  Verify
--  ------
--  See ../README.md → "Verify after apply" section.
--
--  Rollback
--  --------
--  See ../README.md → "Rollback" section. Safe to drop while empty.
-- ============================================================


-- ============================================================
--  TABLE: public.linkedin_accounts
-- ============================================================

CREATE TABLE IF NOT EXISTS public.linkedin_accounts (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Multi-tenant scoping. Both are Clerk identifiers (TEXT, not UUID).
  -- Match the rest of Sellton's schema convention — Clerk owns these IDs.
  organization_id       TEXT NOT NULL,
  user_id               TEXT NOT NULL,                                 -- Clerk userId of the connector

  -- Unipile linkage. The unipile_account_id is the source-of-truth handle
  -- we pass in every Unipile API call to act on this account. Unique
  -- because a Unipile account can only be linked to one Sellton row at
  -- a time (re-connecting deletes + recreates).
  unipile_account_id    TEXT NOT NULL UNIQUE,
  provider              TEXT NOT NULL DEFAULT 'LINKEDIN'
                        CHECK (provider IN (
                          'LINKEDIN',
                          'WHATSAPP',
                          'MESSENGER',
                          'TWITTER',
                          'INSTAGRAM',
                          'TIKTOK'
                        )),

  -- Profile snapshot at connect time. Refreshed opportunistically when
  -- Unipile webhooks fire account.status events. Never used for security
  -- decisions — purely cosmetic for the Settings UI.
  display_name          TEXT,
  profile_url           TEXT,
  profile_picture_url   TEXT,
  headline              TEXT,

  -- LinkedIn account capability tier. Drives what actions are even
  -- possible (e.g. Sales Navigator users have InMail; free accounts
  -- have lower invitation ceilings on LinkedIn's side).
  -- NULL = unknown / not yet inspected.
  account_type          TEXT
                        CHECK (
                          account_type IS NULL OR account_type IN (
                            'free',
                            'premium',
                            'sales_navigator',
                            'recruiter',
                            'business'
                          )
                        ),

  -- Lifecycle state machine. Cron paths skip rows where status != 'active'.
  --   connecting           Hosted-auth started; awaiting callback.
  --   active               Operational; available for campaign assignment.
  --   disconnected         User-initiated disconnect.
  --   credentials_expired  Unipile reports the LinkedIn session was lost.
  --   restricted           LinkedIn flagged the account; cool-down required.
  --   error                Generic non-recoverable failure (rare).
  status                TEXT NOT NULL DEFAULT 'connecting'
                        CHECK (status IN (
                          'connecting',
                          'active',
                          'disconnected',
                          'credentials_expired',
                          'restricted',
                          'error'
                        )),

  -- ARI-aligned: explicit capability discovery without future schema
  -- changes. Populated from Unipile's account-info API when available.
  -- Used to gate UI options in the Tasks/Inbox views.
  -- Example: {"can_send_inmail": true, "can_search_recruiter": false}
  --
  -- IMPORTANT: capabilities NEVER raise our hardcoded safety limits in
  -- src/lib/linkedin-limits.ts. They only decide which actions are
  -- offered to the user, not how many we let through per day.
  capabilities          JSONB NOT NULL DEFAULT '{}'::jsonb,

  -- Free-form bag for everything not worth a column today. Common keys:
  --   timezone                 IANA TZ from LinkedIn profile (scheduler input)
  --   locale                   en_US, etc.
  --   linkedin_provider_id     LinkedIn's stable internal ID for this profile
  --   premium_tier_expires_at  ISO timestamp from LinkedIn premium info
  --   account_creation_year    For trust-tier heuristics (older = safer)
  --
  -- Not for security-relevant data. Not RLS-aware (whole row is RLS-scoped).
  metadata              JSONB NOT NULL DEFAULT '{}'::jsonb,

  -- Lifecycle observability. ARI principle: "If it isn't logged, it
  -- doesn't exist." (SELLTON_GROUND_TRUTH.md §3.3.)
  connected_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  disconnected_at         TIMESTAMPTZ,
  last_synced_at          TIMESTAMPTZ,                                 -- last successful Unipile getAccount call
  last_status_change_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_error_message      TEXT,
  last_error_at           TIMESTAMPTZ,

  -- Standard timestamps.
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- ============================================================
--  INDEXES — covers the four hot paths
-- ============================================================

-- Hot path 1: list a user's connected accounts (Settings → LinkedIn tab).
CREATE INDEX IF NOT EXISTS idx_linkedin_accounts_user_id
  ON public.linkedin_accounts(user_id);

-- Hot path 2: list an org's connected accounts (admin "all team" view,
-- analytics dashboards). Mirrors the inbox view_scope=mine|all pattern.
CREATE INDEX IF NOT EXISTS idx_linkedin_accounts_organization_id
  ON public.linkedin_accounts(organization_id);

-- Hot path 3: webhook lookup. Unipile webhook events arrive with an
-- account_id; we resolve to a Sellton row in O(1) via this index.
-- Already UNIQUE-indexed by the constraint, but a named index lets us
-- reference it in EXPLAIN output.
CREATE INDEX IF NOT EXISTS idx_linkedin_accounts_unipile_id
  ON public.linkedin_accounts(unipile_account_id);

-- Hot path 4: cron filter. Sequence-scheduler iterates only active
-- accounts when computing daily-limit budgets. Partial index keeps it
-- tiny — only rows that actually participate in actions.
CREATE INDEX IF NOT EXISTS idx_linkedin_accounts_active
  ON public.linkedin_accounts(organization_id)
  WHERE status = 'active';


-- ============================================================
--  TRIGGER: maintain updated_at + last_status_change_at
-- ============================================================
--
-- Two-in-one trigger:
--   - updated_at bumps on every row update (standard).
--   - last_status_change_at bumps only when status actually changes
--     (NULL-safe via IS DISTINCT FROM). This gives us a clean signal
--     for cool-down timers (e.g. "restricted for 24h" math) without
--     having to scan linkedin_action_log.

CREATE OR REPLACE FUNCTION public.set_linkedin_accounts_timestamps()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    NEW.last_status_change_at = NOW();
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_linkedin_accounts_timestamps ON public.linkedin_accounts;
CREATE TRIGGER trg_linkedin_accounts_timestamps
  BEFORE UPDATE ON public.linkedin_accounts
  FOR EACH ROW
  EXECUTE FUNCTION public.set_linkedin_accounts_timestamps();


-- ============================================================
--  ROW LEVEL SECURITY
-- ============================================================
--
-- RLS is defense-in-depth. The BFF (Next.js api routes) reads/writes via
-- the Supabase service role, which bypasses RLS. RLS protects against
-- direct REST queries from authenticated Clerk users (anon key + JWT).
--
-- JWT claim path: Clerk Third-Party Auth places identity in standard
-- claims:
--   - auth.jwt() ->> 'sub'     = Clerk userId
--   - auth.jwt() ->> 'org_id'  = Clerk orgId
--
-- These match what BFF reads via @clerk/nextjs/server's getAuth():
--   src/app/api/conversations/route.ts → const { userId, orgId } = ...
--
-- If your Supabase project uses a wrapper helper (e.g. requesting_org_id())
-- instead of direct claim access, swap both USING and WITH CHECK clauses.
-- The function-based form is preferred long-term for testability;
-- inline JWT access is used here for self-containment at slice-1 stage.

ALTER TABLE public.linkedin_accounts ENABLE ROW LEVEL SECURITY;

-- Idempotent re-run: drop before recreate
DROP POLICY IF EXISTS linkedin_accounts_org_select ON public.linkedin_accounts;
DROP POLICY IF EXISTS linkedin_accounts_org_insert ON public.linkedin_accounts;
DROP POLICY IF EXISTS linkedin_accounts_org_update ON public.linkedin_accounts;
DROP POLICY IF EXISTS linkedin_accounts_org_delete ON public.linkedin_accounts;

-- SELECT — any authenticated user in the org sees rows in their org.
-- Matches inbox view_scope='all' shape: org-wide visibility for admin
-- dashboards. Per-user filtering is done in the BFF, not here, so the
-- same policy serves both "my accounts" and "all team accounts" views.
CREATE POLICY linkedin_accounts_org_select
  ON public.linkedin_accounts
  FOR SELECT
  TO authenticated
  USING (organization_id = (auth.jwt() ->> 'org_id'));

-- INSERT — only the connector can create their own row.
-- The BFF callback handler runs as service role and bypasses this; the
-- policy exists so a misconfigured client can't impersonate someone
-- else's connect flow.
CREATE POLICY linkedin_accounts_org_insert
  ON public.linkedin_accounts
  FOR INSERT
  TO authenticated
  WITH CHECK (
    organization_id = (auth.jwt() ->> 'org_id')
    AND user_id    = (auth.jwt() ->> 'sub')
  );

-- UPDATE — within the org. Cross-user updates allowed because admins
-- may need to mark another user's account as 'restricted'. Refine to
-- per-user-only later if RBAC tightens.
CREATE POLICY linkedin_accounts_org_update
  ON public.linkedin_accounts
  FOR UPDATE
  TO authenticated
  USING       (organization_id = (auth.jwt() ->> 'org_id'))
  WITH CHECK  (organization_id = (auth.jwt() ->> 'org_id'));

-- DELETE — only the connector can disconnect their own account.
CREATE POLICY linkedin_accounts_org_delete
  ON public.linkedin_accounts
  FOR DELETE
  TO authenticated
  USING (
    organization_id = (auth.jwt() ->> 'org_id')
    AND user_id    = (auth.jwt() ->> 'sub')
  );


-- ============================================================
--  COMMENTS — visible in Supabase Studio + pg_dump
-- ============================================================

COMMENT ON TABLE public.linkedin_accounts IS
  'Connected Unipile accounts (LinkedIn first; provider column generalizes for WhatsApp/Messenger/etc.). One row per Sellton user per provider account. Status lifecycle drives campaign eligibility; capabilities JSONB supports per-account feature gating without schema change.';

COMMENT ON COLUMN public.linkedin_accounts.unipile_account_id IS
  'Stable identifier issued by Unipile. Pass this in every Unipile API call to operate on this account. Source of truth for the underlying provider session.';

COMMENT ON COLUMN public.linkedin_accounts.provider IS
  'Unipile channel. CHECK constraint enumerates current + reserved values; add new values via migration if Unipile adds a channel.';

COMMENT ON COLUMN public.linkedin_accounts.status IS
  'Lifecycle: connecting (auth in progress) → active (ready) → disconnected | credentials_expired | restricted | error. Cron paths and send routes skip rows where status != ''active''.';

COMMENT ON COLUMN public.linkedin_accounts.capabilities IS
  'Feature flags from Unipile, e.g. {"can_send_inmail": true}. UI uses these to gate options. NEVER raises hardcoded safety limits in src/lib/linkedin-limits.ts.';

COMMENT ON COLUMN public.linkedin_accounts.metadata IS
  'Free-form JSONB: timezone (working-window scheduler input), locale, linkedin_provider_id, premium tier expiry, etc. Not for security-relevant data.';

COMMENT ON COLUMN public.linkedin_accounts.last_status_change_at IS
  'Bumped automatically by trigger when status column changes. Used by cool-down timers (e.g. "restricted for 24h") without scanning linkedin_action_log.';


-- ============================================================
--  Schema cache reload — PostgREST
-- ============================================================
--
-- Without this, REST queries against the new table return PGRST204
-- ("relation not found") until the next automatic schema-cache TTL
-- (~10 min). Lesson learned this session — every migration ends with
-- this line.
NOTIFY pgrst, 'reload schema';
