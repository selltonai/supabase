-- ============================================================
--  Migration: 252_create_cron_config_table
--  Date:      2026-05-06
--  Author:    Sellton AI — LinkedIn V3 / P1-1
--  Plan ref:  /Ground Truth/LINKEDIN_V3_EXECUTION_PLAN.md §3 P1-1
-- ============================================================
--
--  Purpose
--  -------
--  Phase 1 of 2 for the LinkedIn-sequence cron scheduler. Creates the
--  required Postgres extensions and the private config table the
--  cron job will read from.
--
--  Why this is split from the actual cron schedule (252b)
--  ------------------------------------------------------
--  Supabase's SQL editor runs the entire script as one implicit
--  transaction. If we put the schema/table creation AND a RAISE-on-
--  missing-config guard in the same migration, the RAISE rolls back
--  the table creation along with everything else — leaving the user
--  in a state where the error message tells them to INSERT into a
--  table that no longer exists.
--
--  Splitting into two files means:
--    1. THIS migration (252) creates the table and always succeeds.
--    2. The user INSERTs the two config rows.
--    3. The follow-up migration (252b) reads the config + schedules
--       the cron. If config is missing, 252b RAISEs cleanly without
--       affecting the persisted table.
--
--  Idempotency: re-runnable.
--
--  Verify (after apply):
--    \dn sellton_internal                         -- schema exists
--    \d sellton_internal.cron_config              -- table exists with key/value/desc/updated_at
--    SELECT extname FROM pg_extension WHERE extname IN ('pg_cron','pg_net');  -- both present
--
--  Rollback:
--    DROP TABLE IF EXISTS sellton_internal.cron_config;
--    DROP SCHEMA IF EXISTS sellton_internal;
-- ============================================================

-- Extensions required by 252b (the schedule). Enable here so the
-- user only has to enable via Supabase dashboard once. Both are
-- standard Supabase extensions; no extra cost.
--
-- Note: in Supabase the dashboard "enable" toggle is the canonical
-- path. CREATE EXTENSION IF NOT EXISTS is a safety net — if the
-- extension isn't available in the project, this will error with a
-- clear message pointing the user to the dashboard.
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Private schema for Sellton-internal infrastructure config.
-- Not exposed via PostgREST.
CREATE SCHEMA IF NOT EXISTS sellton_internal;

-- Config table — the cron job (created by migration 252b) reads
-- from here at firing time, so the secret can be rotated by an
-- UPDATE without re-creating the schedule.
CREATE TABLE IF NOT EXISTS sellton_internal.cron_config (
  key         TEXT PRIMARY KEY,
  value       TEXT NOT NULL,
  description TEXT,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Lock down the schema + table. Service-role only; never exposed
-- through the PostgREST API surface.
REVOKE ALL ON SCHEMA sellton_internal FROM PUBLIC, anon, authenticated;
GRANT USAGE ON SCHEMA sellton_internal TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON sellton_internal.cron_config TO service_role;
REVOKE ALL ON sellton_internal.cron_config FROM PUBLIC, anon, authenticated;

COMMENT ON TABLE sellton_internal.cron_config IS
  'V3 P1-1. Holds runtime config the pg_cron sequence claimer reads on every firing. Two required keys: public_app_url, internal_cron_api_key. Populate via INSERT before running migration 252b.';

NOTIFY pgrst, 'reload schema';
