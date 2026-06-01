-- ============================================================
--  Migration: 265_add_linkedin_threads_fk_constraints
--  Date:      2026-05-13
--  Author:    Sellton AI — Outreach Intelligence Sprint 1.5 follow-up
--  Plan ref:  Ground Truth/OUTREACH_INTELLIGENCE_QUICK_TEST_PLAN.md
--             (PGRST200 error surfaced during Test 4 validation)
-- ============================================================
--
--  Purpose
--  -------
--  Add the two FK constraints that migration 247 deliberately deferred:
--
--    linkedin_threads.contact_id  → contacts(id)
--    linkedin_threads.campaign_id → campaigns(id)
--
--  Migration 247 explicitly documented the deferral
--  (`247_create_linkedin_threads.sql:70-72`):
--
--    "No FK constraints because the contacts/campaigns table structure
--     is assumed but not introspected by this migration. FKs can be
--     added later via a follow-up ALTER if the schema-management
--     decision settles on enforcing them."
--
--  This is that follow-up.
--
--  Why now
--  -------
--  The conversations API at `selltonai/src/app/api/conversations/
--  route.ts:110-117` uses PostgREST's embedded-query syntax:
--
--    .select("id, ..., contacts:contact_id (firstname, lastname, ...)")
--
--  PostgREST cannot infer this embedded relationship without an
--  explicit FK declaration in the database. The query was failing
--  in production with PGRST200:
--
--    "Searched for a foreign key relationship between
--     'linkedin_threads' and 'contact_id' in the schema 'public',
--     but no matches were found."
--
--  Adding the FKs lets PostgREST infer the relationship and the
--  embedded query works with zero code change.
--
--  ON DELETE SET NULL choice
--  --------------------------
--  Both columns are NULLABLE (linkedin_threads can exist without
--  being attached to a Sellton-tracked contact or campaign — e.g.,
--  unrelated_inbound threads that arrive via webhook from the
--  user's personal LinkedIn DMs). On contact or campaign deletion
--  we want to KEEP the thread row (it's forensic data; the inbox
--  needs it) but null the FK so the row doesn't reference a
--  deleted entity.
--
--  This matches the existing CASCADE behavior of other LinkedIn
--  tables: `linkedin_action_log.linkedin_action_id ON DELETE SET
--  NULL` (migration 245), `campaign_contacts.linkedin_account_id
--  ON DELETE SET NULL` (migration 248). Consistent with the
--  "preserve forensic rows on parent delete" pattern.
--
--  NOT VALID + VALIDATE — why split
--  ---------------------------------
--  `ADD CONSTRAINT ... NOT VALID` takes a brief ACCESS EXCLUSIVE
--  lock to add the constraint definition without scanning existing
--  rows. Subsequent INSERTs/UPDATEs are validated normally; only
--  pre-existing rows are exempt.
--
--  `VALIDATE CONSTRAINT` then takes a SHARE UPDATE EXCLUSIVE lock
--  (concurrent reads + writes OK) and scans existing rows. If all
--  pass, the constraint becomes fully enforced.
--
--  Splitting the two minimizes the disruptive lock window.
--
--  Pre-apply orphan check (verified before this migration was
--  authored — both queries returned 0):
--
--    -- Contact orphans
--    SELECT COUNT(*) FROM linkedin_threads lt
--    LEFT JOIN contacts c ON c.id = lt.contact_id
--    WHERE lt.contact_id IS NOT NULL AND c.id IS NULL;
--
--    -- Campaign orphans
--    SELECT COUNT(*) FROM linkedin_threads lt
--    LEFT JOIN campaigns ca ON ca.id = lt.campaign_id
--    WHERE lt.campaign_id IS NOT NULL AND ca.id IS NULL;
--
--  If either returns > 0 in your environment, VALIDATE CONSTRAINT
--  will error. Resolution options (in order of preference):
--
--    1. NULL the orphan FK values (preserves the threads):
--         UPDATE linkedin_threads SET contact_id = NULL
--         WHERE contact_id NOT IN (SELECT id FROM contacts);
--
--    2. Delete the orphan rows (if forensics aren't needed):
--         DELETE FROM linkedin_threads
--         WHERE contact_id IS NOT NULL
--           AND contact_id NOT IN (SELECT id FROM contacts);
--
--    3. Leave the constraint as `NOT VALID` permanently — enforces
--       on new inserts but tolerates the existing orphans. PostgREST
--       still infers the relationship from a NOT VALID constraint.
--
--  Verify (after apply):
--
--    SELECT conname, confrelid::regclass as references_table,
--           pg_get_constraintdef(oid) as definition
--    FROM pg_constraint
--    WHERE conrelid = 'public.linkedin_threads'::regclass
--      AND contype = 'f'
--    ORDER BY conname;
--
--    -- Expected: 2 rows
--    -- linkedin_threads_campaign_id_fkey  → public.campaigns
--    -- linkedin_threads_contact_id_fkey   → public.contacts
--
--  And confirm PostgREST schema cache picked it up (~30s after
--  apply on Supabase, or trigger a manual reload via NOTIFY pgrst):
--
--    NOTIFY pgrst, 'reload schema';
--
--  Rollback:
--    ALTER TABLE public.linkedin_threads
--      DROP CONSTRAINT IF EXISTS linkedin_threads_contact_id_fkey;
--    ALTER TABLE public.linkedin_threads
--      DROP CONSTRAINT IF EXISTS linkedin_threads_campaign_id_fkey;
--
--  Idempotent: re-runnable. The DO blocks guard against duplicate
--  constraint creation. If the constraint already exists (re-apply
--  scenario), the DO block skips silently.
-- ============================================================

-- Contact FK
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'linkedin_threads_contact_id_fkey'
      AND conrelid = 'public.linkedin_threads'::regclass
  ) THEN
    ALTER TABLE public.linkedin_threads
      ADD CONSTRAINT linkedin_threads_contact_id_fkey
      FOREIGN KEY (contact_id)
      REFERENCES public.contacts(id)
      ON DELETE SET NULL
      NOT VALID;

    ALTER TABLE public.linkedin_threads
      VALIDATE CONSTRAINT linkedin_threads_contact_id_fkey;
  END IF;
END
$$;

-- Campaign FK
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'linkedin_threads_campaign_id_fkey'
      AND conrelid = 'public.linkedin_threads'::regclass
  ) THEN
    ALTER TABLE public.linkedin_threads
      ADD CONSTRAINT linkedin_threads_campaign_id_fkey
      FOREIGN KEY (campaign_id)
      REFERENCES public.campaigns(id)
      ON DELETE SET NULL
      NOT VALID;

    ALTER TABLE public.linkedin_threads
      VALIDATE CONSTRAINT linkedin_threads_campaign_id_fkey;
  END IF;
END
$$;

-- Force PostgREST schema cache reload (Supabase auto-detects, but
-- this triggers it immediately so the embedded query unblocks
-- without a 30s wait).
NOTIFY pgrst, 'reload schema';

COMMENT ON CONSTRAINT linkedin_threads_contact_id_fkey ON public.linkedin_threads IS
  'V3 P0 follow-up — FK deferred by migration 247 (header line 70-72). Added 2026-05-13 to unblock the conversations API embedded query at selltonai/src/app/api/conversations/route.ts:110. ON DELETE SET NULL preserves the thread row for forensics when the contact is deleted.';

COMMENT ON CONSTRAINT linkedin_threads_campaign_id_fkey ON public.linkedin_threads IS
  'V3 P0 follow-up — FK deferred by migration 247 (header line 70-72). Added 2026-05-13 alongside the contact_id FK for consistency. ON DELETE SET NULL — same forensic-preservation rationale as the contact_id FK.';
