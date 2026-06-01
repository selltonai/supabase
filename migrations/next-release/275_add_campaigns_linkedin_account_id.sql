-- ============================================================
--  Migration: 262_add_campaigns_linkedin_account_id
--  Date:      2026-05-12
--  Author:    Sellton AI — LinkedIn integration V3 / Phase 5
--  Plan ref:  /Ground Truth/LINKEDIN_V3_PHASE_5_REDESIGN.md  §10.1
-- ============================================================
--
--  Purpose
--  -------
--  Add an explicit `linkedin_account_id` column to `campaigns` so the
--  campaign creator can pin the LinkedIn account the campaign sends
--  from at wizard time. Strict per-user ownership: the wizard's
--  selector filters by the creator's own accounts; admins do NOT get
--  a relaxed selector.
--
--  Why this exists
--  ---------------
--  Pre-Phase-5, three auto-pick routes (discovered, auto-enroll,
--  campaigns/start) selected LinkedIn accounts via the "most-recently-
--  connected active account in the org" heuristic. When two users in
--  the same org each connect a LinkedIn account, this produced cross-
--  user dispatch (e.g. 2026-05-12: Borce's campaign dispatched from
--  Milka's account). Bug O / Bug O-2 catalogue.
--
--  Post-Phase-5, the wizard's account selector writes this column
--  explicitly. Dispatch reads it as source of truth and auto-reroutes
--  the journey if its stored binding diverges (self-healing).
--
--  Schema choice notes
--  -------------------
--    NULL allowed:
--      - Legacy campaigns created before this migration have NULL
--      - Backfill SQL (see §10.7 of the redesign doc) populates from
--        the most-common journey binding per campaign
--      - Draft campaigns may exist before the wizard reaches the
--        account-selection step
--
--    REFERENCES linkedin_accounts(id) ON DELETE SET NULL:
--      - If the bound account is disconnected from Unipile and its
--        row is deleted, the campaign survives but the column clears
--      - Dispatch then refuses to send (clear error) until the
--        campaign owner rebinds a new account
--      - Prevents orphan FK references
--
--    Partial index on non-NULL:
--      - The dispatch path queries `WHERE linkedin_account_id = X`
--        frequently; partial index keeps cost low without indexing
--        the (large) NULL set for legacy campaigns
--
--  Verify (after apply):
--    SELECT column_name, is_nullable, data_type
--    FROM information_schema.columns
--    WHERE table_name='campaigns' AND column_name='linkedin_account_id';
--      -- Returns: linkedin_account_id | YES | uuid
--
--    SELECT indexname
--    FROM pg_indexes
--    WHERE tablename='campaigns' AND indexname='idx_campaigns_linkedin_account_id';
--      -- Returns: 1 row
--
--  Rollback:
--    ALTER TABLE public.campaigns DROP COLUMN IF EXISTS linkedin_account_id;
--    DROP INDEX IF EXISTS idx_campaigns_linkedin_account_id;
--
--  Idempotent: re-runnable.
-- ============================================================

ALTER TABLE public.campaigns
  ADD COLUMN IF NOT EXISTS linkedin_account_id UUID NULL
  REFERENCES public.linkedin_accounts(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_campaigns_linkedin_account_id
  ON public.campaigns(linkedin_account_id)
  WHERE linkedin_account_id IS NOT NULL;

COMMENT ON COLUMN public.campaigns.linkedin_account_id IS
  'V3 Phase 5.1 — explicit LinkedIn account binding chosen by the campaign creator at wizard time. Filtered to the creator''s own connected accounts (strict ownership; no admin override). NULL for legacy campaigns or drafts; dispatch falls back to journey-level binding when NULL. ON DELETE SET NULL: account disconnection clears this without dropping the campaign. See Ground Truth/LINKEDIN_V3_PHASE_5_REDESIGN.md §10.1.';
