-- ============================================================
-- Migration: 362_backfill-contact-linkedin-provider-id
-- Date:      2026-08-11
-- Purpose:   Populate contacts.linkedin_provider_id from linkedin_threads so
--            inbound LinkedIn replies resolve to a contact on the fast path.
-- Projects:  selltonai-database/supabase (owner), selltonai (reader).
-- Contract:  Data-only backfill. Fills NULLs, never overwrites.
-- Depends:   none (additive UPDATE).
--
-- Why
-- ---
-- Inbound reply → contact resolution (linkedin-counterpart-resolution.ts) tries
-- contacts.linkedin_provider_id first, then a journey-cache fallback. Measured
-- in production 2026-08-11: only 1,384 of 9,391 contacts had the column set, so
-- almost everything depended on the fallback — and the fallback only matches
-- journeys whose state_metadata cached the counterpart URN, which many do not.
-- The consequence was severe and silent: 100% of review_reply tasks had
-- contact_id NULL, so the CRM pipeline stage never advanced (KAN-256), LinkedIn
-- conversations never appeared under a person (KAN-203), and declining a reply
-- could not stop the journey.
--
-- linkedin_threads already holds BOTH sides of the mapping (contact_id and
-- counterpart_provider_id) on the same row — 926 of 1,462 threads carried a
-- contact_id that resolution was re-deriving from scratch and discarding. This
-- promotes that known-good data onto the canonical column, which is exactly
-- what the application's own write-back
-- (backfillContactProviderId) does one row at a time when it gets a journey hit.
--
-- Safety
-- ------
--  * fills only NULLs — a populated value is authoritative, and a mismatch
--    would mean a contact-merge situation this must not silently "fix";
--  * DISTINCT ON picks ONE provider id per contact (most recently updated
--    thread) so a contact with several threads cannot produce an ambiguous or
--    order-dependent result;
--  * skips any provider id already held by a DIFFERENT contact in the same org.
--    The DDL for this column is not captured in this repo (it exists in prod but
--    no migration defines it), so a unique index may exist that this repo cannot
--    see. Skipping collisions makes the backfill correct either way, and leaves
--    genuine duplicates for a human instead of guessing.
-- ============================================================

WITH candidate AS (
  SELECT DISTINCT ON (t.contact_id)
         t.contact_id,
         t.organization_id,
         t.counterpart_provider_id
  FROM public.linkedin_threads t
  WHERE t.contact_id IS NOT NULL
    AND t.counterpart_provider_id IS NOT NULL
    AND length(btrim(t.counterpart_provider_id)) > 0
  ORDER BY t.contact_id, t.updated_at DESC NULLS LAST
)
UPDATE public.contacts c
SET linkedin_provider_id = candidate.counterpart_provider_id
FROM candidate
WHERE c.id = candidate.contact_id
  AND c.organization_id = candidate.organization_id
  AND c.linkedin_provider_id IS NULL
  -- Do not claim a URN another contact in this org already owns.
  AND NOT EXISTS (
    SELECT 1
    FROM public.contacts other
    WHERE other.organization_id = candidate.organization_id
      AND other.linkedin_provider_id = candidate.counterpart_provider_id
      AND other.id <> c.id
  );

-- Verify after apply — expect with_provider_id to have risen materially from
-- the 1,384 / 9,391 measured on 2026-08-11:
-- SELECT count(*) AS contacts, count(linkedin_provider_id) AS with_provider_id
-- FROM public.contacts;
--
-- Threads whose contact still has no URN (these are the rows a future resolver
-- change must handle; they had no usable counterpart_provider_id):
-- SELECT count(*) FROM public.linkedin_threads t
-- JOIN public.contacts c ON c.id = t.contact_id
-- WHERE t.contact_id IS NOT NULL AND c.linkedin_provider_id IS NULL;
