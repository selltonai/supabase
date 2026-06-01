-- ============================================================
--  Migration: 258_add_linkedin_action_log_dispatch_columns
--  Date:      2026-05-06
--  V3 P0-L — close the silent dispatch-log gap.
--
--  Problem
--  -------
--  src/lib/linkedin-task-dispatch.ts has been writing to columns
--  that linkedin_action_log doesn't have (the original 243 schema
--  didn't include them; they were referenced in code but the migration
--  was never written). Result: every successful Unipile send produces
--  a Postgres "column does not exist" error from the action-log
--  insert, which the dispatcher swallows as best-effort. Sends still
--  succeed, but the audit trail loses the provider IDs needed to
--  reconcile webhooks with our outbound calls.
--
--  Columns added (all NULLABLE — best-effort attribution):
--
--    provider_action_id      TEXT
--      Unipile-side action id returned by sendInvitation /
--      sendMessage. Lets us match a webhook back to the originating
--      send.
--
--    provider_message_id     TEXT
--      Unipile-side message id (returned for sendMessage; null for
--      sendInvitation since invitations aren't messages).
--
--    unipile_chat_id         TEXT
--      Provider chat/thread id when the send happened on an existing
--      thread or auto-created one. Cross-link to linkedin_threads.
--
--    counterpart_provider_id TEXT
--      The recipient's LinkedIn member id. Denormalized for fast
--      "what did this account send to this person today" queries.
--
--    metadata                JSONB
--      Free-form per-send context (task_id, text_length,
--      campaign_contact_id, autopilot, etc.). Mirrors the metadata
--      shape every other Sellton table uses.
--
--  Backfill: NULL for existing rows. The columns are forensic
--  signals — historical rows lacking them is acceptable; new rows
--  get them populated as sends happen.
--
--  Idempotent: ADD COLUMN IF NOT EXISTS.
--
--  Verify (after apply):
--    SELECT column_name, data_type
--      FROM information_schema.columns
--     WHERE table_name = 'linkedin_action_log'
--       AND column_name IN (
--         'provider_action_id',
--         'provider_message_id',
--         'unipile_chat_id',
--         'counterpart_provider_id',
--         'metadata'
--       );
--    -- expect 5 rows
-- ============================================================

ALTER TABLE public.linkedin_action_log
  ADD COLUMN IF NOT EXISTS provider_action_id      TEXT,
  ADD COLUMN IF NOT EXISTS provider_message_id     TEXT,
  ADD COLUMN IF NOT EXISTS unipile_chat_id         TEXT,
  ADD COLUMN IF NOT EXISTS counterpart_provider_id TEXT,
  ADD COLUMN IF NOT EXISTS metadata                JSONB;

COMMENT ON COLUMN public.linkedin_action_log.provider_action_id IS
  'V3 P0-L. Unipile-side action id returned by sendInvitation / sendMessage. Cross-references webhook events.';

COMMENT ON COLUMN public.linkedin_action_log.provider_message_id IS
  'V3 P0-L. Unipile-side message id. Populated for sendMessage; NULL for sendInvitation (invitations are not messages).';

COMMENT ON COLUMN public.linkedin_action_log.unipile_chat_id IS
  'V3 P0-L. Provider chat/thread id at send time. Joins to linkedin_threads.unipile_chat_id for thread-level analytics.';

COMMENT ON COLUMN public.linkedin_action_log.counterpart_provider_id IS
  'V3 P0-L. Recipient LinkedIn member id. Denormalized for fast forensic queries on per-account, per-recipient send history.';

COMMENT ON COLUMN public.linkedin_action_log.metadata IS
  'V3 P0-L. Free-form per-send context. Shape: { source, task_id, text_length, campaign_contact_id, autopilot? }. Same JSONB pattern other Sellton tables use.';

-- Index supporting the webhook reconciliation pattern: incoming
-- account-status webhook events that reference an unipile_chat_id
-- can quickly find recent sends on that thread.
CREATE INDEX IF NOT EXISTS idx_linkedin_action_log_chat
  ON public.linkedin_action_log(unipile_chat_id, created_at DESC)
  WHERE unipile_chat_id IS NOT NULL;

NOTIFY pgrst, 'reload schema';
