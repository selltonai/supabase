-- ============================================================
--  Migration: 259_add_linkedin_enrichment_columns
--  Date:      2026-05-06
--  V3 P1-A — LinkedIn enrichment data layer (Phase 1 + Phase 2 scaffold).
--
--  Plan ref: Ground Truth/LINKEDIN_V3_ENRICHMENT_PLAN.md §6
--
--  Adds two columns and one constraint:
--
--    contacts.linkedin_signals  JSONB
--      Per-contact LinkedIn signals that don't fit the existing
--      `linkedin_profile` shape. Specifically Unipile-sourced fields:
--      network_distance, mutual_connections, last_unipile_fetch.
--      Default {} (so existing rows get a valid empty shape).
--
--    campaigns.enrichment_tier  TEXT
--      Per-campaign enrichment policy. v3.1 default 'basic' = only
--      free-during-cold-resolve fields. 'full' = auto-fetch mutual
--      connections + posts at enrolment time (Phase 3+).
--      ARI replaces this with a selective-fetch agent (Phase 5).
--
--  Why JSONB and not a wide schema:
--    The data shape evolves rapidly during Phase 1-4 build-out
--    (mutual connections, network distance, recent posts). JSONB
--    lets us add fields without migrations. Provenance shape
--    `{value, source, fetched_at}` per top-level key — see
--    src/lib/linkedin-enrichment-merge.ts for canonical reader/writer.
--
--  RLS:
--    `contacts` and `campaigns` already have RLS enabled at the row
--    level (org-scoped). New columns inherit the table's RLS — no
--    additional policy needed.
--
--  Idempotent:
--    ADD COLUMN IF NOT EXISTS, IF NOT EXISTS on the CHECK constraint.
--    Re-running on already-migrated DB is a no-op.
--
--  Rollback (safe — columns are NULL-tolerant):
--    ALTER TABLE public.contacts  DROP COLUMN IF EXISTS linkedin_signals;
--    ALTER TABLE public.campaigns DROP COLUMN IF EXISTS enrichment_tier;
-- ============================================================

ALTER TABLE public.contacts
  ADD COLUMN IF NOT EXISTS linkedin_signals JSONB DEFAULT '{}'::jsonb;

COMMENT ON COLUMN public.contacts.linkedin_signals IS
  'V3 P1-A — Unipile-sourced LinkedIn signals (network_distance, mutual_connections, last_unipile_fetch). Provenance shape: each top-level key is { value, source, fetched_at }. Read/write via src/lib/linkedin-enrichment-merge.ts. Empty default {} so legacy rows are valid.';

-- Lightweight index — rarely-queried column, but supports the future
-- ARI agent's "stale enrichment" scans without a sequential read. The
-- expression matches the canonical fetched_at timestamp populated by
-- linkedin-enrichment-merge.ts.
CREATE INDEX IF NOT EXISTS idx_contacts_linkedin_signals_last_fetch
  ON public.contacts ((linkedin_signals->>'last_unipile_fetch'))
  WHERE linkedin_signals IS NOT NULL
    AND linkedin_signals != '{}'::jsonb;

ALTER TABLE public.campaigns
  ADD COLUMN IF NOT EXISTS enrichment_tier TEXT DEFAULT 'basic';

-- CHECK constraint — gate the value space so adapter code can switch
-- safely. ALTER…ADD CONSTRAINT lacks IF NOT EXISTS in older Postgres,
-- so we do drop+add for idempotency.
ALTER TABLE public.campaigns
  DROP CONSTRAINT IF EXISTS campaigns_enrichment_tier_check;

ALTER TABLE public.campaigns
  ADD CONSTRAINT campaigns_enrichment_tier_check
  CHECK (enrichment_tier IN ('basic', 'full'));

COMMENT ON COLUMN public.campaigns.enrichment_tier IS
  'V3 P1-A — enrichment policy. ''basic'' (default): free-during-cold-resolve only (network_distance via resolveProfile). ''full'': Phase 3+ auto-fetch mutual connections + posts at enrolment time (billed). ARI Phase 5 replaces this with a selective-fetch agent.';

NOTIFY pgrst, 'reload schema';
