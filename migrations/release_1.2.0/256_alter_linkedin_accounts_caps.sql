-- ============================================================
--  Migration: 244_alter_linkedin_accounts_caps
--  Date:      2026-04-28
--  Author:    Sellton AI — LinkedIn integration Cycle 1 / Phase 2.5
--  Plan ref:  /Ground Truth/LINKEDIN_INTEGRATION_PLAN_V2.md  §3.3 (D4 alt)
--  Depends:   240_create_linkedin_accounts.sql
-- ============================================================
--
--  Purpose
--  -------
--  Make the per-day caps adjustable per-account from the frontend, so the
--  test user can iterate without redeploys. NULL columns mean "use the
--  hardcoded LINKEDIN_LIMITS default" — preserves plan decision D4 in
--  production while enabling fast tuning during dev testing.
--
--  Resolution order in code (linkedin-rate-limiter.ts):
--    1. The DB column on this row, if non-null.
--    2. NEXT_PUBLIC_LINKEDIN_TEST_MODE env override, if set.
--    3. LINKEDIN_LIMITS hardcoded constants.
--
--  Idempotent: ADD COLUMN IF NOT EXISTS.
--
--  Rollback:
--    ALTER TABLE public.linkedin_accounts
--      DROP COLUMN IF EXISTS daily_invite_cap,
--      DROP COLUMN IF EXISTS daily_message_cap;
-- ============================================================

ALTER TABLE public.linkedin_accounts
  ADD COLUMN IF NOT EXISTS daily_invite_cap   INTEGER,
  ADD COLUMN IF NOT EXISTS daily_message_cap  INTEGER;

-- Constrain to sane values. NULL means "fall through to defaults".
-- 0 is allowed and explicitly means "do not send" — useful kill switch.
ALTER TABLE public.linkedin_accounts
  DROP CONSTRAINT IF EXISTS linkedin_accounts_invite_cap_range;
ALTER TABLE public.linkedin_accounts
  ADD CONSTRAINT linkedin_accounts_invite_cap_range
  CHECK (daily_invite_cap IS NULL OR (daily_invite_cap >= 0 AND daily_invite_cap <= 200));

ALTER TABLE public.linkedin_accounts
  DROP CONSTRAINT IF EXISTS linkedin_accounts_message_cap_range;
ALTER TABLE public.linkedin_accounts
  ADD CONSTRAINT linkedin_accounts_message_cap_range
  CHECK (daily_message_cap IS NULL OR (daily_message_cap >= 0 AND daily_message_cap <= 500));

COMMENT ON COLUMN public.linkedin_accounts.daily_invite_cap IS
  'Per-account override for daily invitation send cap. NULL falls through to LINKEDIN_LIMITS / test-mode env defaults. 0 disables sending without disconnecting.';

COMMENT ON COLUMN public.linkedin_accounts.daily_message_cap IS
  'Per-account override for daily message send cap. NULL falls through to LINKEDIN_LIMITS / test-mode env defaults. 0 disables sending without disconnecting.';

NOTIFY pgrst, 'reload schema';
