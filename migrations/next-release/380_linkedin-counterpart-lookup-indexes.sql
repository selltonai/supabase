-- ============================================================
-- Migration: linkedin-counterpart-lookup-indexes (main: release_1.3.0/372, stage: next-release/380 — byte-identical)
-- Date:      2026-09-23
-- Purpose:   Index the LinkedIn counterpart (member URN) lookups that run on
--            every inbound LinkedIn message and relation event.
-- Projects:  selltonai-database/supabase (owner); readers: selltonai
--            (linkedin-campaign-scope, linkedin-counterpart-resolution,
--            linkedin-relation-transition, linkedin-manual-takeover,
--            invites/withdraw, linkedin-task-dispatch) and selltonai-modal
--            (reply_handler_service._linkedin_campaign_scoped).
-- Contract:  Index-only. No column, constraint, RLS, request, response, auth,
--            webhook, cron or queue contract changes. Safe to drop.
-- Depends:   public.campaign_contacts (260), public.linkedin_action_log
--            (255 + 271 counterpart_provider_id), public.linkedin_threads (259).
--
-- Why: the KAN-153 campaign-scope gate (2026-09-23) decides, per inbound DM and
-- per new connection, whether the counterpart was ever part of a Sellton
-- campaign. Its counterpart lookups — and the pre-existing resolver / relation
-- lookups on the same keys — had no index and ran as org-wide filter scans:
--   campaign_contacts   organization_id|linkedin_account_id = ?
--                       AND (contact_id = ? OR state_metadata->>'recipient_provider_id' = ?
--                            OR state_metadata->>'linkedin_provider_id' = ?)
--   linkedin_action_log organization_id|unipile_account_id = ? AND counterpart_provider_id = ?
--   linkedin_threads    organization_id|unipile_account_id = ? AND counterpart_provider_id = ?
--
-- Design:
-- - Keyed on the URN alone. A LinkedIn member URN identifies one person, so it
--   is selective on its own and one index serves both the org-scoped and the
--   account-scoped variants (the scope column is a cheap recheck).
-- - Partial on IS NOT NULL: most rows never carry the key. PostgREST's
--   `col.eq.X` / `->>key.eq.X` compile to a strict `=`, which implies the
--   predicate, so the planner can use these partial indexes.
-- - The legacy state_metadata key `linkedin_provider_id` has no writer today,
--   but every journey lookup ORs it in. A BitmapOr needs an index on EVERY
--   branch; without this one the whole OR falls back to a scan. It is tiny.
-- - campaign_contacts.contact_id gets its own index here. The 51/73
--   idx_campaign_contacts_contact_id died with `DROP TABLE campaign_contacts
--   CASCADE` in 89, and 260 recreated the table without one (its unique index
--   leads with campaign_id). Without it the contact arm of the OR has no index
--   and the whole lookup stays a scan; it also serves pauseJourneyOnReply and
--   Modal's contact_scope_reason / _recover_campaign_id (org + contact_id).
--   IF NOT EXISTS keeps it a no-op where the old index survived.
-- - Expression STATISTICS on the two state_metadata keys. The planner does not
--   use a PARTIAL expression index's stats for row estimates, so without these
--   it guesses 0.5% of the table per URN arm and, under LIMIT 1, prefers an
--   org-wide scan over the BitmapOr. Measured on a 300k-row local replica (PG15):
--   the org-scoped journey lookup stayed a Seq Scan (~25 ms) with the indexes
--   alone and became a BitmapOr (~0.06 ms) once these statistics existed.
-- - ANALYZE at the end so the statistics exist immediately rather than at the
--   next autovacuum (same pattern as 186_add_performance_indexes).
-- - Plain CREATE INDEX (the runner rejects CONCURRENTLY): each build takes a
--   SHARE lock (blocks writes) held until the file's transaction commits. These
--   tables are tens of thousands of rows at most. lock_timeout makes the file
--   fail and roll back instead of queueing every LinkedIn writer behind a
--   long-running transaction; re-run it (idempotent). Apply outside send windows.
--
-- Rollback (safe; nothing depends on these objects):
--   DROP INDEX IF EXISTS public.idx_campaign_contacts_recipient_provider_id,
--     public.idx_campaign_contacts_legacy_linkedin_provider_id,
--     public.idx_linkedin_action_log_counterpart,
--     public.idx_linkedin_threads_counterpart;
--   DROP STATISTICS IF EXISTS public.stx_campaign_contacts_recipient_provider_id,
--     public.stx_campaign_contacts_legacy_linkedin_provider_id;
--   (Leave idx_campaign_contacts_contact_id: it may predate this migration.)
-- ============================================================

SET LOCAL lock_timeout = '10s';

CREATE INDEX IF NOT EXISTS idx_campaign_contacts_contact_id
  ON public.campaign_contacts (contact_id);

CREATE INDEX IF NOT EXISTS idx_campaign_contacts_recipient_provider_id
  ON public.campaign_contacts ((state_metadata ->> 'recipient_provider_id'))
  WHERE (state_metadata ->> 'recipient_provider_id') IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_campaign_contacts_legacy_linkedin_provider_id
  ON public.campaign_contacts ((state_metadata ->> 'linkedin_provider_id'))
  WHERE (state_metadata ->> 'linkedin_provider_id') IS NOT NULL;

CREATE STATISTICS IF NOT EXISTS public.stx_campaign_contacts_recipient_provider_id
  ON ((state_metadata ->> 'recipient_provider_id')) FROM public.campaign_contacts;

CREATE STATISTICS IF NOT EXISTS public.stx_campaign_contacts_legacy_linkedin_provider_id
  ON ((state_metadata ->> 'linkedin_provider_id')) FROM public.campaign_contacts;

CREATE INDEX IF NOT EXISTS idx_linkedin_action_log_counterpart
  ON public.linkedin_action_log (counterpart_provider_id, created_at DESC)
  WHERE counterpart_provider_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_linkedin_threads_counterpart
  ON public.linkedin_threads (counterpart_provider_id)
  WHERE counterpart_provider_id IS NOT NULL;

ANALYZE public.campaign_contacts;
ANALYZE public.linkedin_action_log;
ANALYZE public.linkedin_threads;

-- Verification after apply:
-- SELECT indexname, indexdef
-- FROM pg_indexes
-- WHERE schemaname = 'public'
--   AND indexname IN (
--     'idx_campaign_contacts_contact_id',
--     'idx_campaign_contacts_recipient_provider_id',
--     'idx_campaign_contacts_legacy_linkedin_provider_id',
--     'idx_linkedin_action_log_counterpart',
--     'idx_linkedin_threads_counterpart'
--   );
--
-- SELECT stxname FROM pg_statistic_ext
-- WHERE stxname LIKE 'stx_campaign_contacts_%provider_id';
--
-- Plan check (substitute a real org + URN; expect Bitmap/Index Scans on the new
-- indexes, BitmapOr for the journey lookup):
-- EXPLAIN SELECT id FROM public.campaign_contacts
-- WHERE organization_id = '<org>'
--   AND (contact_id = '00000000-0000-0000-0000-000000000000'
--        OR state_metadata ->> 'recipient_provider_id' = '<urn>'
--        OR state_metadata ->> 'linkedin_provider_id' = '<urn>')
-- LIMIT 1;
-- EXPLAIN SELECT id FROM public.linkedin_action_log
-- WHERE organization_id = '<org>' AND counterpart_provider_id = '<urn>' AND success = true
-- LIMIT 1;
