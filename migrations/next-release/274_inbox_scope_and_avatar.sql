-- ============================================================
--  Migration: 261_inbox_scope_and_avatar
--  Date:      2026-05-12
--  V3 P2 WS6 — close the inbox scope + name + avatar gaps surfaced
--             during stage QA (audit doc §11.1 + §11.2).
--
--  Problems
--  --------
--  1. `linkedin_threads` rows are inserted by the message webhook for
--     every chat the connected LinkedIn account sees — including the
--     user's personal DMs that have nothing to do with Sellton
--     campaigns. The inbox lists all of them.
--
--  2. Inbox UI falls back to the literal string "LinkedIn contact"
--     whenever `linkedin_threads.counterpart_name` is null. There's no
--     second-tier fallback to the `contacts` table's firstname/lastname
--     even though the thread row carries `contact_id`.
--
--  3. No avatar column exists; Unipile sends `attendee_profile_picture_url`
--     on every inbound event but we drop it.
--
--  Changes
--  -------
--  A. New column `linkedin_threads.thread_origin` with CHECK constraint:
--       'sellton_outbound'   — Sellton dispatcher created the thread
--                              (any outbound action we initiated)
--       'campaign_inbound'   — inbound event from a counterpart we
--                              already have as a Sellton contact
--                              (campaign-managed conversation)
--       'unrelated_inbound'  — inbound event from a counterpart NOT in
--                              our contacts table (the user's personal
--                              DMs leaking in via webhook). Kept in DB
--                              so pauseJourneyOnReply still has the
--                              full inbound stream to consult; hidden
--                              from the inbox UI.
--
--  B. New column `counterpart_profile_picture_url` on both
--     `linkedin_threads` and `linkedin_messages`. Webhook normalizer
--     extracts it from Unipile payloads going forward; legacy rows
--     stay NULL until the next inbound event refreshes them.
--
--  C. Backfill thread_origin for existing rows so the inbox query
--     filter doesn't suddenly hide everything:
--       - rows with contact_id NOT NULL → 'campaign_inbound'
--         (any thread that was ever linked to a Sellton contact)
--       - all other rows → 'unrelated_inbound' (default — safe to hide)
--     Outbound-driven threads created BEFORE this migration won't get
--     'sellton_outbound' retroactively (the dispatcher didn't stamp
--     them), but they always have contact_id set, so they correctly
--     land in 'campaign_inbound' via the backfill rule above.
--
--  D. Partial index on the inbox query path:
--       (organization_id, last_message_at DESC)
--       WHERE thread_status='active'
--             AND thread_origin IN ('sellton_outbound', 'campaign_inbound')
--     Replaces / complements the existing index. Cuts read cost on the
--     inbox by skipping the personal-DM portion of the table.
--
--  Idempotency: every statement is IF NOT EXISTS or guarded.
--  Rollback (safe before any new code reads the columns):
--      DROP INDEX IF EXISTS idx_linkedin_threads_inbox_visible;
--      ALTER TABLE linkedin_threads DROP COLUMN IF EXISTS thread_origin;
--      ALTER TABLE linkedin_threads DROP COLUMN IF EXISTS counterpart_profile_picture_url;
--      ALTER TABLE linkedin_messages DROP COLUMN IF EXISTS counterpart_profile_picture_url;
-- ============================================================

BEGIN;

-- ──────────────────────────────────────────────────────────────────────
-- A + B. Schema additions
-- ──────────────────────────────────────────────────────────────────────

ALTER TABLE public.linkedin_threads
  ADD COLUMN IF NOT EXISTS thread_origin TEXT
    CHECK (thread_origin IN (
      'sellton_outbound',
      'campaign_inbound',
      'unrelated_inbound'
    )),
  ADD COLUMN IF NOT EXISTS counterpart_profile_picture_url TEXT;

ALTER TABLE public.linkedin_messages
  ADD COLUMN IF NOT EXISTS counterpart_profile_picture_url TEXT;

COMMENT ON COLUMN public.linkedin_threads.thread_origin IS
  'V3 P2 WS6 — scope tag for inbox filtering. campaign_inbound and sellton_outbound surface in /inbox; unrelated_inbound is hidden but kept in DB so pauseJourneyOnReply has full visibility.';

COMMENT ON COLUMN public.linkedin_threads.counterpart_profile_picture_url IS
  'V3 P2 WS6 — LinkedIn-side avatar URL from Unipile attendee_profile_picture_url. NULL on legacy rows + on outbound-only threads where no inbound event has populated it yet.';

COMMENT ON COLUMN public.linkedin_messages.counterpart_profile_picture_url IS
  'V3 P2 WS6 — per-message snapshot of counterpart avatar. Lets the thread view render the historically-correct avatar per message even if the counterpart later updates their LinkedIn picture.';

-- ──────────────────────────────────────────────────────────────────────
-- C. Backfill — set thread_origin for existing rows
-- ──────────────────────────────────────────────────────────────────────
--
-- The rule below is conservative: rows already linked to a Sellton
-- contact are marked 'campaign_inbound' (visible in inbox). Everything
-- else is 'unrelated_inbound' (hidden). This means:
--
--   - User's pre-existing personal DMs (no contact_id) → hidden ✓
--   - Past Sellton campaign threads that lost contact_id somehow → hidden
--     (rare; would need a manual re-link). Acceptable trade-off; the
--     thread still exists in DB and pauseJourneyOnReply still consults it.
--
-- We use COALESCE-style update: only touch rows where thread_origin IS
-- NULL so a re-run doesn't clobber post-migration writes.

UPDATE public.linkedin_threads
SET thread_origin = CASE
  WHEN contact_id IS NOT NULL THEN 'campaign_inbound'
  ELSE 'unrelated_inbound'
END
WHERE thread_origin IS NULL;

-- ──────────────────────────────────────────────────────────────────────
-- D. Partial index for the inbox query hot path
-- ──────────────────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_linkedin_threads_inbox_visible
  ON public.linkedin_threads(organization_id, last_message_at DESC)
  WHERE thread_status = 'active'
    AND thread_origin IN ('sellton_outbound', 'campaign_inbound');

COMMENT ON INDEX public.idx_linkedin_threads_inbox_visible IS
  'V3 P2 WS6 — inbox list hot path. Excludes unrelated_inbound (the user''s personal LinkedIn DMs) so a 500-DM background doesn''t slow the inbox scan.';

-- ──────────────────────────────────────────────────────────────────────
-- E. PostgREST schema cache nudge
-- ──────────────────────────────────────────────────────────────────────
NOTIFY pgrst, 'reload schema';

COMMIT;

-- ──────────────────────────────────────────────────────────────────────
-- Verification (run manually post-apply)
-- ──────────────────────────────────────────────────────────────────────
--
-- 1. New columns present:
--    \d public.linkedin_threads
--    \d public.linkedin_messages
--
-- 2. Backfill landed:
--    SELECT thread_origin, COUNT(*)
--    FROM public.linkedin_threads
--    GROUP BY 1
--    ORDER BY 1;
--    -- Expect: only 'campaign_inbound' and 'unrelated_inbound' (no NULL)
--
-- 3. Index exists:
--    SELECT indexname FROM pg_indexes
--    WHERE tablename = 'linkedin_threads'
--      AND indexname = 'idx_linkedin_threads_inbox_visible';
--
-- 4. Inbox preview query works (replace <ORG>):
--    SELECT id, counterpart_name, thread_origin
--    FROM public.linkedin_threads
--    WHERE organization_id = '<ORG>'
--      AND thread_status = 'active'
--      AND thread_origin IN ('sellton_outbound', 'campaign_inbound')
--    ORDER BY last_message_at DESC
--    LIMIT 10;
