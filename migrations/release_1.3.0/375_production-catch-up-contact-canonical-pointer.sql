-- ============================================================
-- Migration: production-catch-up-contact-canonical-pointer (main only)
-- Date:      2026-10-27
-- Purpose:   Production never received release_1.2.0/273_contact_dedup_indexes.sql (it has only
--            sellton.normalize_linkedin_url). next-release/406 and 407 read contacts.canonical_contact_id
--            (COALESCE(ct.canonical_contact_id, ct.id)), so 406 fails on production without it.
--            This file adds the self-pointer column and its index exactly as 273 phase 1 does. Every row stays
--            NULL, which 406 and 407 read as "this contact is canonical".
--            Not included, on purpose:
--              - linkedin_url_canonical: no application code reads it, and a STORED generated column rewrites
--                public.contacts.
--              - The two partial unique indexes: production had 39 duplicate (org, LinkedIn URL) groups and 214
--                duplicate (org, lower(email)) groups on 2026-10-27, so they would fail. They need a dedup pass first.
-- Projects:  selltonai-database/supabase (owner). Readers: next-release/406, 407 dashboard functions.
-- Contract:  One nullable column and one partial index. No data change; adding a nullable column without a
--            default does not rewrite the table.
-- Rollback:  DROP INDEX IF EXISTS public.idx_contacts_canonical_pointer;
--            ALTER TABLE public.contacts DROP COLUMN IF EXISTS canonical_contact_id;
-- ============================================================

ALTER TABLE public.contacts
  ADD COLUMN IF NOT EXISTS canonical_contact_id uuid
  REFERENCES public.contacts(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.contacts.canonical_contact_id IS
  'V3 P2 WS2 — points at the canonical contact when this row is a soft-merged duplicate. NULL means this row IS canonical.';

CREATE INDEX IF NOT EXISTS idx_contacts_canonical_pointer
  ON public.contacts(canonical_contact_id)
  WHERE canonical_contact_id IS NOT NULL;
