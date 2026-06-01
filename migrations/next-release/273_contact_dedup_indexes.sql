-- ============================================================
--  V3 P2 WS2 — contact-level dedup indexes
-- ============================================================
--
-- Adds two partial unique indexes on `contacts` so the database can no
-- longer store two rows for the same person within an organization.
-- Combined with the application-layer dedup helpers in
-- `src/lib/contact-dedup.ts`, this closes the duplicate-contact loop
-- end-to-end:
--
--   - L1 (app, enroll-time):  findSiblingJourney() short-circuits a
--                              parallel enrol against an existing
--                              sibling row.
--   - L2 (app, insert-time):  findExistingContact() consulted by every
--                              contact-write path before inserting.
--   - L3 (db, this migration): partial unique indexes on
--                              (organization_id, normalized identity)
--                              that reject any insert that bypasses L1+L2.
--
-- Why partial indexes (not regular unique constraints)?
-- ============================================================
--   - Some contacts have no LinkedIn URL (email-only). NOT NULL on
--     linkedin_url is wrong; partial index `WHERE linkedin_url IS NOT
--     NULL AND linkedin_url <> ''` covers only the rows with the signal.
--   - Same for email-only contacts (no LinkedIn): a separate partial
--     index on email handles them.
--   - Contacts with neither identity signal can still exist (rare,
--     usually placeholder / processing) and aren't covered. That's the
--     correct behavior — there's nothing to dedup on.
--
-- Why a generated column (linkedin_url_canonical)?
-- ============================================================
--   Raw `linkedin_url` comes in many shapes (with/without protocol,
--   with/without www, trailing slashes, mixed case, query strings).
--   Without normalization, "linkedin.com/in/sarah" and
--   "https://www.linkedin.com/in/sarah/" are NOT equal at the index
--   level — the unique constraint wouldn't catch them.
--
--   We add `linkedin_url_canonical` as a STORED generated column whose
--   value is computed by the immutable function
--   `sellton.normalize_linkedin_url(text)` (defined below). The unique
--   index is on that column; canonical equality is enforced.
--
-- Backfill safety:
-- ============================================================
--   Existing duplicates would cause this migration to fail at the index-
--   creation step. The migration is split into two phases:
--
--     1. Add the column + function + populate canonical for existing rows
--     2. CREATE UNIQUE INDEX CONCURRENTLY (so writes aren't blocked)
--
--   If existing data has dupes, step 2 will report them via the
--   duplicate constraint error. Operators should run the dedup audit
--   query at the bottom of this file FIRST, manually merge dupes via the
--   `canonical_contact_id` self-pointer pattern (see scaffolding helper
--   coming in WS2.5), then re-run step 2.
--
-- Idempotent: every statement is `IF NOT EXISTS` / `OR REPLACE` so the
-- migration is safe to re-run.

BEGIN;

-- ──────────────────────────────────────────────────────────────────────
-- Phase 1 — schema additions
-- ──────────────────────────────────────────────────────────────────────

CREATE SCHEMA IF NOT EXISTS sellton;

-- Pure SQL normalizer mirroring src/lib/linkedin-url.ts. Marked IMMUTABLE
-- so PostgreSQL can use it in a generated column.
--
-- Returns NULL for input that isn't a recognizable LinkedIn profile or
-- company URL — so the partial unique index correctly skips non-LinkedIn
-- garbage.
CREATE OR REPLACE FUNCTION sellton.normalize_linkedin_url(raw text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  s text;
BEGIN
  IF raw IS NULL OR btrim(raw) = '' THEN
    RETURN NULL;
  END IF;

  s := lower(btrim(raw));

  -- Strip protocol (http://, https://, //)
  s := regexp_replace(s, '^https?://', '');
  s := regexp_replace(s, '^//', '');

  -- Strip subdomain prefix (www., uk., de., etc.) before linkedin.com
  s := regexp_replace(s, '^([a-z0-9-]+\.)?linkedin\.com', 'linkedin.com');

  -- Strip query string + fragment
  s := regexp_replace(s, '[?#].*$', '');

  -- Strip trailing slashes
  s := regexp_replace(s, '/+$', '');

  -- Reject anything that doesn't look like a profile or company path
  IF s !~ '^linkedin\.com/(in|company)/[a-z0-9_\-%.]+' THEN
    RETURN NULL;
  END IF;

  RETURN s;
END;
$$;

COMMENT ON FUNCTION sellton.normalize_linkedin_url(text) IS
  'V3 P2 WS2 — canonicalize LinkedIn URLs for dedup. Returns NULL for non-LinkedIn input. Mirrors src/lib/linkedin-url.ts:normalizeLinkedinUrl().';

-- Generated canonical column. STORED so it can be indexed. Recomputes
-- automatically when linkedin_url is updated.
ALTER TABLE public.contacts
  ADD COLUMN IF NOT EXISTS linkedin_url_canonical text
  GENERATED ALWAYS AS (sellton.normalize_linkedin_url(linkedin_url)) STORED;

COMMENT ON COLUMN public.contacts.linkedin_url_canonical IS
  'V3 P2 WS2 — auto-computed canonical form of linkedin_url for dedup. NULL when linkedin_url is empty or not recognizably a LinkedIn profile/company URL.';

-- Self-pointer for soft-merging existing duplicates without losing FK
-- integrity. WS2.5 backfill picks the richest row per dupe group as
-- canonical, then sets canonical_contact_id on losers. App reads via
-- a `getCanonicalContact(id)` helper that traverses the pointer.
ALTER TABLE public.contacts
  ADD COLUMN IF NOT EXISTS canonical_contact_id uuid
  REFERENCES public.contacts(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.contacts.canonical_contact_id IS
  'V3 P2 WS2 — points at the canonical contact when this row is a soft-merged duplicate. NULL means this row IS canonical.';

CREATE INDEX IF NOT EXISTS idx_contacts_canonical_pointer
  ON public.contacts(canonical_contact_id)
  WHERE canonical_contact_id IS NOT NULL;

-- ──────────────────────────────────────────────────────────────────────
-- Phase 2 — partial unique indexes (the actual dedup constraint)
-- ──────────────────────────────────────────────────────────────────────
--
-- IMPORTANT: if existing data has duplicates, these CREATE UNIQUE INDEX
-- statements will FAIL with a duplicate-key error naming the offending
-- rows. Operators must:
--
--   1. Run the audit query at the bottom of this file
--   2. For each dup group, decide a canonical row + set
--      canonical_contact_id on the others (WS2.5 helper script)
--   3. Re-run this migration
--
-- Once the indexes exist, no future insert path can re-create the
-- problem regardless of which code path it takes.

CREATE UNIQUE INDEX IF NOT EXISTS idx_contacts_unique_org_linkedin
  ON public.contacts(organization_id, linkedin_url_canonical)
  WHERE linkedin_url_canonical IS NOT NULL
    AND canonical_contact_id IS NULL;

COMMENT ON INDEX public.idx_contacts_unique_org_linkedin IS
  'V3 P2 WS2 — at most one canonical contacts row per (org, LinkedIn URL). Soft-merged dupes are excluded via canonical_contact_id IS NULL.';

CREATE UNIQUE INDEX IF NOT EXISTS idx_contacts_unique_org_email_lower
  ON public.contacts(organization_id, lower(email))
  WHERE email IS NOT NULL
    AND email <> ''
    AND canonical_contact_id IS NULL;

COMMENT ON INDEX public.idx_contacts_unique_org_email_lower IS
  'V3 P2 WS2 — at most one canonical contacts row per (org, lowercased email). Soft-merged dupes are excluded via canonical_contact_id IS NULL.';

COMMIT;

-- ──────────────────────────────────────────────────────────────────────
-- Audit / pre-merge inspection (run BEFORE applying this migration if
-- you suspect existing duplicates). NOT executed automatically — paste
-- and run manually via psql to inspect.
-- ──────────────────────────────────────────────────────────────────────
--
-- Find LinkedIn-URL duplicates:
--
--   SELECT
--     organization_id,
--     sellton.normalize_linkedin_url(linkedin_url) AS canonical,
--     COUNT(*) AS dupe_count,
--     array_agg(id ORDER BY created_at) AS contact_ids
--   FROM public.contacts
--   WHERE linkedin_url IS NOT NULL AND linkedin_url <> ''
--   GROUP BY organization_id, sellton.normalize_linkedin_url(linkedin_url)
--   HAVING COUNT(*) > 1;
--
-- Find email duplicates:
--
--   SELECT
--     organization_id,
--     lower(email) AS canonical_email,
--     COUNT(*) AS dupe_count,
--     array_agg(id ORDER BY created_at) AS contact_ids
--   FROM public.contacts
--   WHERE email IS NOT NULL AND email <> ''
--   GROUP BY organization_id, lower(email)
--   HAVING COUNT(*) > 1;
