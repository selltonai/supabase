-- ============================================================
--  Migration: 248_create_campaign_contacts
--  Date:      2026-05-05
--  Author:    Sellton AI — LinkedIn integration V3 / Phase B
--  Plan ref:  /Ground Truth/LINKEDIN_INTEGRATION_EXECUTION_PLAN_V3.md  §6.4, §12
--  Build log: /Ground Truth/LINKEDIN_V3_BUILD_LOG.md  §4 → Phase B
--  Depends:   240_create_linkedin_accounts.sql (only — no FK to contacts/campaigns,
--             see "Cross-table FKs" note below)
-- ============================================================
--
--  Purpose
--  -------
--  One orchestration row per (campaign, contact) pair. Home of the
--  channel-aware journey state machine that drives LinkedIn outreach
--  and (eventually) channel-fallback decisions.
--
--  Why this exists separately from campaign_emails:
--    • Email is per-message; this is per-journey.
--    • Reply on one channel must pause future actions on another channel.
--      That cross-channel pause cannot be encoded on a per-message row;
--      it belongs at the (campaign, contact) level. (V3 §12.4)
--    • LinkedIn invite-then-message has DELAY semantics (wait for
--      acceptance, then schedule message) that don't fit campaign_emails.
--
--  V3 §4.5 explicitly defers the campaign_emails → campaign_messages
--  rename. campaign_emails stays as-is. campaign_contacts is added
--  ALONGSIDE, not as a replacement. Email step rows in campaign_emails
--  will eventually link to a campaign_sequence_actions row that links
--  here; for V1 the link is forward-compatible but optional.
--
--  Cross-table FKs
--  ---------------
--  No FKs to `contacts` or `campaigns` because:
--    • This migration is ordering-independent (can apply on any DB
--      regardless of whether contacts/campaigns tables happen to be
--      named differently or use a different ID type).
--    • If those tables are ever migrated in production, FK-on-cascade
--      drops are scarier than orphan rows the application can clean up.
--  The application layer is responsible for treating
--  contact_id/campaign_id as soft references.
--
--  Idempotency: re-runnable.
--
--  Verify (after apply):
--    SELECT * FROM campaign_contacts LIMIT 0;                                 -- columns load
--    SELECT relrowsecurity FROM pg_class WHERE relname='campaign_contacts';   -- t
--    SELECT count(*) FROM pg_indexes WHERE tablename='campaign_contacts';     -- 5 (PK + 4)
--
--  Rollback: DROP TABLE IF EXISTS public.campaign_contacts CASCADE;
-- ============================================================


CREATE TABLE IF NOT EXISTS public.campaign_contacts (
  id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Soft references to Sellton's existing contacts/campaigns tables.
  -- Application enforces validity; no DB FK constraint (see header).
  campaign_id              UUID NOT NULL,
  contact_id               UUID NOT NULL,

  -- Tenant scoping (Clerk-managed identifiers; TEXT per Sellton convention).
  organization_id          TEXT NOT NULL,
  owner_user_id            TEXT NOT NULL,            -- whose seat this journey runs from

  -- Optional link to a connected LinkedIn account. Nullable because:
  --   • Email-only campaigns have no LinkedIn seat.
  --   • LinkedIn account may not be connected yet at journey-creation time.
  -- ON DELETE SET NULL: keep the journey row if the account is later
  -- disconnected. The journey may pivot to email-only fallback or pause.
  linkedin_account_id      UUID
                           REFERENCES public.linkedin_accounts(id)
                           ON DELETE SET NULL,

  -- Journey state machine. The full enum may grow over time; CHECK
  -- enumerates the v1 minimum and is expandable via ALTER ... DROP/ADD
  -- CONSTRAINT in a follow-up migration.
  journey_state            TEXT NOT NULL DEFAULT 'pending'
                           CHECK (journey_state IN (
                             'pending',           -- created; nothing started yet
                             'queued_invite',     -- next action: send LinkedIn invite (waiting cron)
                             'invited',           -- invite sent; waiting acceptance
                             'accepted',          -- connection accepted; next action: first message
                             'queued_message',    -- next action: send message (waiting cron)
                             'messaged',          -- message sent; waiting reply
                             'replied',           -- counterpart replied (paused)
                             'declined',          -- invite declined or counterpart blocked
                             'failed',            -- terminal failure (account restricted, etc.)
                             'completed',         -- all planned steps done
                             'cancelled'          -- explicitly cancelled by user
                           )),

  -- Where in the configured campaign sequence this journey is. Nullable
  -- when journey_state = 'pending' before any steps have run.
  current_step             INTEGER
                           CHECK (current_step IS NULL OR current_step >= 0),

  -- When the next action becomes eligible. Worker claim queries filter by
  -- (status='ready' AND next_action_at <= now()). NULL means no scheduled
  -- next action (terminal state or paused indefinitely).
  next_action_at           TIMESTAMPTZ,

  -- If LinkedIn step fails or is blocked, fall back to this channel.
  -- For v1 the only meaningful value is 'email'; left open for future.
  fallback_channel         TEXT
                           CHECK (fallback_channel IS NULL
                                  OR fallback_channel IN ('email', 'none')),

  -- Snapshot of LinkedIn relation state at the journey level (mirrors
  -- linkedin_threads.relation_state but kept here too so the worker can
  -- decide eligibility without joining).
  relation_state           TEXT
                           CHECK (relation_state IS NULL OR relation_state IN (
                             'unknown', 'invited', 'connected',
                             'declined', 'withdrawn', 'blocked'
                           )),

  -- Free-form journey metadata (e.g. last_error, retry_count, copy_overrides).
  state_metadata           JSONB NOT NULL DEFAULT '{}'::jsonb,

  created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at               TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- ============================================================
--  CONSTRAINTS
-- ============================================================

-- One journey per (campaign, contact) — there cannot be two parallel
-- LinkedIn sequences for the same person in the same campaign.
CREATE UNIQUE INDEX IF NOT EXISTS idx_campaign_contacts_unique
  ON public.campaign_contacts(campaign_id, contact_id);


-- ============================================================
--  INDEXES — worker claim + dashboard reads
-- ============================================================

-- Worker claim hot path: "what's due in the next batch?". Partial index
-- keeps it cheap by excluding terminal states.
CREATE INDEX IF NOT EXISTS idx_campaign_contacts_due
  ON public.campaign_contacts(next_action_at)
  WHERE next_action_at IS NOT NULL
    AND journey_state NOT IN ('completed', 'cancelled', 'failed', 'declined', 'replied');

-- Org/journey-state filter for admin dashboards.
CREATE INDEX IF NOT EXISTS idx_campaign_contacts_org_state
  ON public.campaign_contacts(organization_id, journey_state);

-- Per-account view (which journeys are running on this LinkedIn seat).
CREATE INDEX IF NOT EXISTS idx_campaign_contacts_account
  ON public.campaign_contacts(linkedin_account_id)
  WHERE linkedin_account_id IS NOT NULL;

-- Per-campaign view.
CREATE INDEX IF NOT EXISTS idx_campaign_contacts_campaign
  ON public.campaign_contacts(campaign_id, updated_at DESC);


-- ============================================================
--  RLS
-- ============================================================

ALTER TABLE public.campaign_contacts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS campaign_contacts_org_select ON public.campaign_contacts;

CREATE POLICY campaign_contacts_org_select
  ON public.campaign_contacts
  FOR SELECT
  TO authenticated
  USING (organization_id = (auth.jwt() ->> 'org_id'));

-- INSERT/UPDATE/DELETE: BFF/worker only via service role.


-- ============================================================
--  COMMENTS
-- ============================================================

COMMENT ON TABLE public.campaign_contacts IS
  'Per-(campaign, contact) journey orchestration row. Heart of the channel-aware sequence engine. V3 §6.4, §12.';

COMMENT ON COLUMN public.campaign_contacts.journey_state IS
  'V1 enum. Expandable in future migrations as new modes (LinkedIn-then-email-fallback parallel, etc.) are wired up. Worker logic reads this to decide eligibility.';

COMMENT ON COLUMN public.campaign_contacts.next_action_at IS
  'Set by the worker after each step transition. Worker claim query: WHERE next_action_at <= now() AND journey_state NOT IN (terminal). Partial index supports this pattern.';

COMMENT ON COLUMN public.campaign_contacts.fallback_channel IS
  'V1: only "email" or NULL. The configured campaign mode determines whether falling back to email is allowed when a LinkedIn step is blocked.';

COMMENT ON COLUMN public.campaign_contacts.relation_state IS
  'Mirrors linkedin_threads.relation_state at the journey level so the worker does not need a join to decide invite vs message eligibility.';

COMMENT ON COLUMN public.campaign_contacts.state_metadata IS
  'Free-form JSONB. Suggested keys: last_error, retry_count, copy_overrides, channel_strategy, fallback_triggered_at.';


NOTIFY pgrst, 'reload schema';
