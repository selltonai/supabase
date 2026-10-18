-- Migration: 401_crm-delete-foreign-key-indexes
-- Ticket: KAN-334. Built as 395 on 2026-10-14; renumbered because stage holds 394-399.
-- KAN-334: indexes on the referencing columns that a company or contact delete scans without one.
-- Owner: selltonai-database/supabase. Consumer: crm_list_delete_batch (400) and every single company or
-- contact delete. No app change. Request/response and auth unchanged.
--
-- Without these, each deleted company scans ai_ark_enrollment_runs, deals and unmatched_replies, and each
-- deleted contact scans deal_activities, deals, crm_deal_projection_failures and unmatched_replies. That is
-- why a batch of 100 hit the 8 s statement timeout on 2026-10-14.
--
-- Plain CREATE INDEX (the runner refuses CONCURRENTLY): each one blocks writes to its table while it builds.
-- Read the production row counts before the merge (plan section 4.3); all seven tables are expected small.
-- lock_timeout makes the file fail instead of queueing behind a long transaction (a queued lock blocks readers).
--
-- Rollback: rollback/400-401_crm-list-delete-and-move.rollback.sql.

SET LOCAL lock_timeout = '5s';

-- companies(id)
CREATE INDEX IF NOT EXISTS idx_ai_ark_enrollment_runs_company_id
  ON public.ai_ark_enrollment_runs (company_id);
CREATE INDEX IF NOT EXISTS idx_deals_company_id
  ON public.deals (company_id);
CREATE INDEX IF NOT EXISTS idx_unmatched_replies_resolved_company_id
  ON public.unmatched_replies (resolved_company_id)
  WHERE resolved_company_id IS NOT NULL;

-- contacts(id)
CREATE INDEX IF NOT EXISTS idx_deal_activities_contact_id
  ON public.deal_activities (contact_id)
  WHERE contact_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_deals_stage_contact_id
  ON public.deals (stage_contact_id)
  WHERE stage_contact_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_crm_deal_projection_failures_contact_id
  ON public.crm_deal_projection_failures (contact_id)
  WHERE contact_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_unmatched_replies_resolved_contact_id
  ON public.unmatched_replies (resolved_contact_id)
  WHERE resolved_contact_id IS NOT NULL;

-- Verification after apply (read-only, on stage, by a developer with database access):
-- BEGIN; EXPLAIN (ANALYZE, BUFFERS) DELETE FROM public.companies WHERE id = '<company of a test list>'; ROLLBACK;
-- BEGIN; EXPLAIN (ANALYZE, BUFFERS) DELETE FROM public.contacts WHERE id = '<contact of a test list>'; ROLLBACK;
-- Pass: each under 100 ms, and no Seq Scan on the seven tables above in the trigger/FK plans.
