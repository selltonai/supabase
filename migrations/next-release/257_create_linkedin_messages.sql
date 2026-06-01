-- ============================================================
--  Migration: 245_create_linkedin_messages
--  Date:      2026-04-28
--  Author:    Sellton AI — LinkedIn integration Cycle 1 / Phase 2.5
--  Plan ref:  /Ground Truth/LINKEDIN_INTEGRATION_PLAN_V2.md  §6.3
--  Depends:   240_create_linkedin_accounts.sql
-- ============================================================
--
--  Purpose
--  -------
--  Storage for LinkedIn conversation events — initially inbound only
--  (cycle 1 ships the message webhook). Outbound writes will land here
--  in cycle 2 when the review-task → send pipeline is wired in.
--
--  Why a new table rather than reusing `messages`/`conversations`:
--    - The existing email tables aren't renamed (plan D5 deferred). We're
--      explicitly not touching email schema during the LinkedIn buildout.
--    - When the rename happens at Phase 5 rollout, this table merges in
--      under a `channel` column. Keeping LinkedIn-specifics
--      (counterpart_provider_id, unipile_chat_id) here means the merge
--      is a column rename, not a data restructure.
--
--  Idempotent: CREATE TABLE IF NOT EXISTS, CREATE INDEX IF NOT EXISTS.
--
--  Verify (after apply):
--    SELECT * FROM linkedin_messages LIMIT 0;                              -- columns load
--    SELECT relrowsecurity FROM pg_class WHERE relname='linkedin_messages';-- t
--    SELECT count(*) FROM pg_indexes WHERE tablename='linkedin_messages';  -- 4
--
--  Rollback (safe while empty):
--    DROP TABLE IF EXISTS public.linkedin_messages CASCADE;
-- ============================================================


CREATE TABLE IF NOT EXISTS public.linkedin_messages (
  id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Multi-tenant scoping. Mirrors linkedin_accounts/linkedin_action_log.
  organization_id          TEXT NOT NULL,
  user_id                  TEXT NOT NULL,            -- account owner

  -- Sellton-side parent. CASCADE on delete: removing the account removes
  -- the conversation history with it (matches linkedin_action_log).
  linkedin_account_id      UUID NOT NULL
                           REFERENCES public.linkedin_accounts(id)
                           ON DELETE CASCADE,
  unipile_account_id       TEXT NOT NULL,             -- denormalized for fast queries

  -- Unipile identifiers.
  unipile_chat_id          TEXT,                      -- thread / conversation ID
  unipile_message_id       TEXT UNIQUE,               -- prevents dup webhook deliveries
  linkedin_action_id       UUID
                           REFERENCES public.linkedin_action_log(id)
                           ON DELETE SET NULL,        -- when this message was OUR send

  -- The other party in the conversation. For inbound messages, this is
  -- the sender; for outbound, the recipient. Same column avoids two-table
  -- denormalization.
  direction                TEXT NOT NULL
                           CHECK (direction IN ('inbound', 'outbound')),
  counterpart_provider_id  TEXT,
  counterpart_name         TEXT,
  counterpart_url          TEXT,

  -- Message body. Plain text from Unipile. Full raw_payload kept for
  -- forensics + future schema evolution without losing fidelity.
  text                     TEXT,
  raw_payload              JSONB,

  -- Time the event happened (Unipile timestamp when present, else server now).
  occurred_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  -- Time we wrote the row (always server now).
  created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- ============================================================
--  INDEXES
-- ============================================================

-- Inbox listing per account, newest first.
CREATE INDEX IF NOT EXISTS idx_linkedin_messages_account_recent
  ON public.linkedin_messages(unipile_account_id, occurred_at DESC);

-- Thread listing — fetch a chat by id ordered by time.
CREATE INDEX IF NOT EXISTS idx_linkedin_messages_chat
  ON public.linkedin_messages(unipile_chat_id, occurred_at ASC)
  WHERE unipile_chat_id IS NOT NULL;

-- Org-wide queries.
CREATE INDEX IF NOT EXISTS idx_linkedin_messages_org
  ON public.linkedin_messages(organization_id, occurred_at DESC);

-- Inbound-only filter for "show unread replies" badges.
CREATE INDEX IF NOT EXISTS idx_linkedin_messages_inbound
  ON public.linkedin_messages(unipile_account_id, occurred_at DESC)
  WHERE direction = 'inbound';


-- ============================================================
--  RLS — same shape as linkedin_accounts and linkedin_action_log
-- ============================================================

ALTER TABLE public.linkedin_messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS linkedin_messages_org_select ON public.linkedin_messages;

-- SELECT — org-scoped. The account owner's user_id is on the row, so the
-- inbox UI can further filter to "my messages" via WHERE user_id = ...
-- without needing a separate policy.
CREATE POLICY linkedin_messages_org_select
  ON public.linkedin_messages
  FOR SELECT
  TO authenticated
  USING (organization_id = (auth.jwt() ->> 'org_id'));

-- INSERT/UPDATE/DELETE: BFF-only via service role. Webhook handlers bypass
-- RLS to write inbound rows. No authenticated-client write policy.


-- ============================================================
--  COMMENTS
-- ============================================================

COMMENT ON TABLE public.linkedin_messages IS
  'LinkedIn conversation events. Cycle 1: inbound only (webhook-fed). Cycle 2+: outbound rows added when review-task approval triggers a send. Forms the basis for inbox surfacing of LinkedIn threads.';

COMMENT ON COLUMN public.linkedin_messages.unipile_message_id IS
  'Unipile''s stable identifier for this message. UNIQUE so dup webhook deliveries (Unipile retries) become no-ops via ON CONFLICT DO NOTHING.';

COMMENT ON COLUMN public.linkedin_messages.linkedin_action_id IS
  'For outbound rows, the audit-log row that produced this send. Lets us reconcile "what we sent" with "what arrived". NULL for inbound.';

COMMENT ON COLUMN public.linkedin_messages.counterpart_provider_id IS
  'Unipile provider_id of the OTHER party — sender for inbound, recipient for outbound. Same column for both directions avoids a two-shape model.';


NOTIFY pgrst, 'reload schema';
