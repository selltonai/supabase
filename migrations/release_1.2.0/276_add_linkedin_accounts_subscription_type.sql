-- ============================================================
--  Migration: 263_add_linkedin_accounts_subscription_type
--  Date:      2026-05-12
--  Author:    Sellton AI — LinkedIn integration V3 / Phase 5.3
--  Plan ref:  /Ground Truth/LINKEDIN_V3_PHASE_5_REDESIGN.md  §3
-- ============================================================
--
--  Purpose
--  -------
--  Add `subscription_type` to `linkedin_accounts` so the dispatch
--  validator + Modal copywriter can apply the correct LinkedIn
--  invitation note character limit per account tier.
--
--  LinkedIn enforces tier-specific char caps on connection notes:
--
--    Free / Premium Career / Premium Business  → 200 chars
--    Sales Navigator Core / Advanced           → 300 chars
--    Recruiter Lite / Recruiter                → 300 chars
--
--  Pre-Phase-5.3, the BFF dispatcher capped at the lowest common
--  ceiling (200 chars) universally. This rejected legitimate 250+
--  character invites from Sales Navigator accounts that LinkedIn
--  would have accepted. Operator confirmed 2026-05-12 that Borce's
--  account (Borce Manev) has Sales Nav and the 200-char cap was
--  arbitrarily blocking valid 250-char drafts.
--
--  Why operator-declared (not auto-detected)
--  -----------------------------------------
--  Unipile's `GET /api/v1/accounts/{id}` does NOT expose subscription
--  type or tier capabilities (audited 2026-05-12). The operator owns
--  this information ("I have Sales Nav, I'm paying for it") and a
--  single dropdown at connection time is the cleanest, most reliable
--  signal. Future enhancement could attempt empirical detection (try
--  300, fall back on rejection) but that burns invite slots.
--
--  Schema choice notes
--  -------------------
--    NULL allowed:
--      - Legacy accounts pre-migration have NULL → dispatch falls
--        back to the lowest-common 200-char limit (safe default)
--      - New connections start NULL → operator picks from a dropdown
--        in Settings → LinkedIn after connecting
--
--    CHECK constraint:
--      - Enum-style: only the documented LinkedIn tier values
--      - 'unknown' included for accounts that genuinely don't know
--        (some Recruiter seats, Enterprise admin-managed, etc.)
--
--  Verify (after apply):
--    SELECT column_name, is_nullable, data_type
--    FROM information_schema.columns
--    WHERE table_name='linkedin_accounts' AND column_name='subscription_type';
--      -- Returns: subscription_type | YES | text
--
--    SELECT constraint_name
--    FROM information_schema.table_constraints
--    WHERE table_name='linkedin_accounts'
--      AND constraint_name='linkedin_accounts_subscription_type_check';
--      -- Returns: 1 row
--
--  Rollback:
--    ALTER TABLE public.linkedin_accounts
--      DROP CONSTRAINT IF EXISTS linkedin_accounts_subscription_type_check;
--    ALTER TABLE public.linkedin_accounts
--      DROP COLUMN IF EXISTS subscription_type;
--
--  Idempotent: re-runnable.
-- ============================================================

ALTER TABLE public.linkedin_accounts
  ADD COLUMN IF NOT EXISTS subscription_type TEXT NULL;

-- Add CHECK constraint (only if not already present — Supabase doesn't
-- have IF NOT EXISTS for ADD CONSTRAINT, so wrap in DO block).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE table_name = 'linkedin_accounts'
      AND constraint_name = 'linkedin_accounts_subscription_type_check'
  ) THEN
    ALTER TABLE public.linkedin_accounts
      ADD CONSTRAINT linkedin_accounts_subscription_type_check
      CHECK (subscription_type IS NULL OR subscription_type IN (
        'free',
        'premium_career',
        'premium_business',
        'sales_navigator_core',
        'sales_navigator_advanced',
        'recruiter_lite',
        'recruiter',
        'unknown'
      ));
  END IF;
END
$$;

COMMENT ON COLUMN public.linkedin_accounts.subscription_type IS
  'V3 Phase 5.3 — LinkedIn account subscription tier. Drives the per-account invitation note character cap (200 for free/premium-non-nav; 300 for Sales Navigator / Recruiter). Operator-declared via the Settings → LinkedIn dropdown since Unipile does not expose subscription type via API. NULL falls back to the conservative 200-char cap. See Ground Truth/LINKEDIN_V3_PHASE_5_REDESIGN.md §3.';
