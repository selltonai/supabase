-- Migration: 319_add_contacts_linkedin_profile
-- Description: Add the missing `contacts.linkedin_profile` JSONB column.
--
--   The LinkedIn enrichment code reads AND writes `contacts.linkedin_profile`
--   (the canonical store for Unipile-sourced profile data — display name,
--   headline, location, industry, summary, picture, provider_id, etc., merged
--   via src/lib/linkedin-enrichment-merge.ts). Migration 272
--   (`272_add_linkedin_enrichment_columns.sql`) even documents linkedin_signals
--   as "fields that don't fit the existing `linkedin_profile` shape" — i.e. it
--   ASSUMED linkedin_profile already existed. But NO migration ever created it
--   (full_schema.sql confirms `contacts` has only `linkedin_url`; the only
--   `linkedin_profile` in the schema is `organization_settings.company_linkedin_profile`,
--   a different column).
--
--   Symptom: the contact page's "Refresh from LinkedIn" button hit
--   `POST /api/linkedin/contacts/[id]/refresh`, whose first query is
--   `select id, organization_id, linkedin_url, linkedin_profile, linkedin_signals`.
--   PostgREST returned a column-not-found error → the route's contactErr branch
--   returned `{ error: "Failed to load contact" }` (500), surfaced as the toast
--   the user saw. The contact lookup never even reached the Unipile resolve.
--
--   This forward, idempotent migration creates the column so the refresh flow
--   (and the sequence claim route, which also selects linkedin_profile) works.
-- Author: reconciliation (prod drift fix)
-- Date: 2026-06-02

-- 1. The genuinely-missing column. JSONB with {} default (provenance shape:
--    each top-level key is { value, source, fetched_at }) so legacy rows are
--    valid and the enrichment merge can write into it.
ALTER TABLE public.contacts
  ADD COLUMN IF NOT EXISTS linkedin_profile JSONB DEFAULT '{}'::jsonb;

COMMENT ON COLUMN public.contacts.linkedin_profile IS
  'Unipile-sourced LinkedIn profile enrichment (display_name, headline, location, industry, summary, profile_picture_url, provider_id). Provenance shape: each top-level key is { value, source, fetched_at }. Read/write via src/lib/linkedin-enrichment-merge.ts. Empty default {} so legacy rows are valid.';

-- 2. Defensive: ensure `linkedin_signals` too. Migration 272 adds it, but it
--    has drifted before in this project (cf. 125→318) and the refresh route
--    selects BOTH columns — a single missing one fails the whole SELECT. No-op
--    where 272 already ran.
ALTER TABLE public.contacts
  ADD COLUMN IF NOT EXISTS linkedin_signals JSONB DEFAULT '{}'::jsonb;

-- 3. Reload the PostgREST schema cache so the API sees the column immediately
--    (the route was failing with a column-not-found until the cache reloaded).
NOTIFY pgrst, 'reload schema';
