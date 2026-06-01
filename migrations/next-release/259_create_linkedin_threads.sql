-- ============================================================
--  Migration: 247_create_linkedin_threads
--  Date:      2026-05-05
--  Author:    Sellton AI — LinkedIn integration V3 / Phase B
--  Plan ref:  /Ground Truth/LINKEDIN_INTEGRATION_EXECUTION_PLAN_V3.md  §6.3, §10
--  Build log: /Ground Truth/LINKEDIN_V3_BUILD_LOG.md  §4 → Phase B
--  Depends:   240_create_linkedin_accounts.sql
-- ============================================================
--
--  Purpose
--  -------
--  Summary table for LinkedIn conversation threads. Inbox does NOT
--  re-derive threads from raw `linkedin_messages` on every load — it
--  reads from this summary, which the message webhook keeps current via
--  upsert.
--
--  Without this table, the conversations list would re-aggregate
--  potentially thousands of message rows on every inbox open, ordered
--  by latest, grouped by chat. That gets slow fast and produces
--  inconsistent unread counts under concurrent inbound deliveries.
--
--  Update model
--  ------------
--  Treat as a materialized summary owned by the message webhook handler:
--    • UPSERT on `unipile_chat_id` for each inbound message.
--    • Set `last_message_at`, `last_message_preview` (≤200 chars),
--      `last_direction='inbound'`.
--    • Increment `unread_count` for inbound; DO NOT increment for
--      outbound rows we just sent ourselves.
--    • On outbound send (Phase D writes the linkedin_messages row), the
--      same upsert clears unread_count to 0.
--
--  Relation state
--  --------------
--  Tracked here in addition to linkedin_messages so the inbox can
--  display "not yet connected" / "request pending" UX without joining
--  to an action log on every read.
--
--  Idempotency: re-runnable via CREATE TABLE/INDEX IF NOT EXISTS.
--
--  Verify (after apply):
--    SELECT * FROM linkedin_threads LIMIT 0;                                 -- columns load
--    SELECT relrowsecurity FROM pg_class WHERE relname='linkedin_threads';   -- t
--    SELECT count(*) FROM pg_indexes WHERE tablename='linkedin_threads';     -- 6 (PK + 5)
--
--  Rollback: DROP TABLE IF EXISTS public.linkedin_threads CASCADE;
-- ============================================================


CREATE TABLE IF NOT EXISTS public.linkedin_threads (
  id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Multi-tenant scoping. Mirrors linkedin_accounts/linkedin_messages.
  organization_id          TEXT NOT NULL,
  owner_user_id            TEXT NOT NULL,             -- account owner

  -- Sellton-side parent. Threads belong to a connected account.
  -- ON DELETE SET NULL: keep thread history when the account is later
  -- disconnected so admin/inbox views can still show "ex-conversation"
  -- without referencing a now-missing account row. This is opposite of
  -- linkedin_messages which CASCADEs — by V3 §6.3 the THREAD summary is
  -- forensic-grade like provider_event_log, not transient like raw
  -- messages.
  linkedin_account_id      UUID
                           REFERENCES public.linkedin_accounts(id)
                           ON DELETE SET NULL,

  -- Sellton-side cross-references — nullable; populated when the inbox
  -- has matched the LinkedIn counterpart to an existing contact/campaign.
  -- No FK constraints because the contacts/campaigns table structure is
  -- assumed but not introspected by this migration. FKs can be added
  -- later via a follow-up ALTER if the schema-management decision settles
  -- on enforcing them.
  contact_id               UUID,
  campaign_id              UUID,

  -- Provider-side identifiers (denormalized for efficient queries).
  unipile_account_id       TEXT NOT NULL,
  unipile_chat_id          TEXT NOT NULL,           -- the chat thread; UNIQUE below

  -- The other party in the conversation.
  counterpart_provider_id  TEXT,
  counterpart_name         TEXT,
  counterpart_url          TEXT,

  -- Recency snapshot (updated on every message webhook).
  last_message_at          TIMESTAMPTZ,
  last_message_preview     TEXT,                     -- truncated to ≤200 chars
  last_direction           TEXT
                           CHECK (last_direction IN ('inbound', 'outbound')),
  unread_count             INTEGER NOT NULL DEFAULT 0
                           CHECK (unread_count >= 0),

  -- Connection-state snapshot. Updated by relation webhook handler and
  -- by send-of-invitation success. Distinct from linkedin_action_log
  -- which is per-attempt; this column is "current state of relationship".
  relation_state           TEXT
                           CHECK (relation_state IN (
                             'unknown',
                             'invited',         -- invitation sent, awaiting response
                             'connected',       -- accepted / 1st-degree
                             'declined',        -- explicitly rejected
                             'withdrawn',       -- we cancelled the invite
                             'blocked'          -- counterpart blocked us
                           )),

  -- Lifecycle status of the thread itself.
  thread_status            TEXT NOT NULL DEFAULT 'active'
                           CHECK (thread_status IN ('active', 'archived', 'flagged')),

  metadata                 JSONB NOT NULL DEFAULT '{}'::jsonb,

  created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at               TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- ============================================================
--  CONSTRAINTS — uniqueness on the natural key
-- ============================================================

-- One thread row per Unipile chat thread. Upserts use this as the
-- conflict target. Putting it on its own line as a unique index (not
-- inline UNIQUE) so we can drop/recreate independently if we ever need to
-- migrate without touching the table itself.
CREATE UNIQUE INDEX IF NOT EXISTS idx_linkedin_threads_chat_unique
  ON public.linkedin_threads(unipile_chat_id);


-- ============================================================
--  INDEXES — built around the inbox's hot path
-- ============================================================

-- Org-wide inbox listing, newest first. Powers `view_scope=all`.
CREATE INDEX IF NOT EXISTS idx_linkedin_threads_org_recent
  ON public.linkedin_threads(organization_id, last_message_at DESC NULLS LAST);

-- "My threads" — the default view for non-admin users (V3 §10.2).
CREATE INDEX IF NOT EXISTS idx_linkedin_threads_owner_recent
  ON public.linkedin_threads(owner_user_id, last_message_at DESC NULLS LAST);

-- Campaign-scoped read for campaign deep links and dashboards.
CREATE INDEX IF NOT EXISTS idx_linkedin_threads_campaign
  ON public.linkedin_threads(campaign_id, last_message_at DESC NULLS LAST)
  WHERE campaign_id IS NOT NULL;

-- Contact-scoped read for "all conversations with this person" views.
CREATE INDEX IF NOT EXISTS idx_linkedin_threads_contact
  ON public.linkedin_threads(contact_id)
  WHERE contact_id IS NOT NULL;

-- Unread badge — partial index keeps it cheap once the dataset grows.
CREATE INDEX IF NOT EXISTS idx_linkedin_threads_unread
  ON public.linkedin_threads(owner_user_id, last_message_at DESC)
  WHERE unread_count > 0;


-- ============================================================
--  RLS
-- ============================================================

ALTER TABLE public.linkedin_threads ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS linkedin_threads_org_select ON public.linkedin_threads;

-- SELECT — org members see their org's threads. The BFF layer further
-- filters to per-user (`view_scope=mine`) when the user is not an org admin
-- (V3 §10.2). This RLS is the floor.
CREATE POLICY linkedin_threads_org_select
  ON public.linkedin_threads
  FOR SELECT
  TO authenticated
  USING (organization_id = (auth.jwt() ->> 'org_id'));

-- INSERT/UPDATE/DELETE: BFF/webhook only via service role. Users don't
-- mutate inbox summaries directly.


-- ============================================================
--  COMMENTS
-- ============================================================

COMMENT ON TABLE public.linkedin_threads IS
  'Per-chat summary row. Materialized by the message webhook so inbox listing is O(threads) not O(messages). V3 §6.3, §10.';

COMMENT ON COLUMN public.linkedin_threads.unipile_chat_id IS
  'Unipile-side chat/thread identifier. The natural primary key for upserts driven by inbound message events.';

COMMENT ON COLUMN public.linkedin_threads.last_message_preview IS
  'Truncated to ≤200 chars by the application before insert. Storage cap is not enforced at the column level (TEXT) so we tolerate occasional larger values without failing the row.';

COMMENT ON COLUMN public.linkedin_threads.relation_state IS
  'Current connection state of the conversation. Distinct from linkedin_action_log (per-attempt audit). Updated by the relation webhook handler and by successful invitation sends.';

COMMENT ON COLUMN public.linkedin_threads.unread_count IS
  'Maintained by the message webhook: incremented on direction=inbound, reset to 0 when the inbox UI marks the thread as read OR when an outbound message is sent on this thread (the user has clearly seen recent inbound by then).';


NOTIFY pgrst, 'reload schema';
