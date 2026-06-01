-- ============================================================
--  Migration: 250_add_campaigns_channel_strategy
--  Date:      2026-05-06
--  Author:    Sellton AI — LinkedIn V3 / P0-1
--  Plan ref:  /Ground Truth/LINKEDIN_V3_EXECUTION_PLAN.md §2 P0-1
--             /Ground Truth/LINKEDIN_V3_INTEGRATION_REVIEW.updated.md §4.1, §8.1
-- ============================================================
--
--  Purpose
--  -------
--  Adds `channel_strategy` to the campaigns table so the create
--  wizard can capture (and the workflow builder + sequence engine
--  can consume) the user's explicit channel choice:
--
--    'linkedin' — LinkedIn-only campaigns (V3 P0 launch target)
--    'email'    — existing email-only behavior (default for legacy rows)
--    'mixed'    — LinkedIn + email parallel/fallback (gated; v1.1)
--
--  Backwards compatibility
--  -----------------------
--  Column is nullable. Every existing campaign row is treated as
--  `channel_strategy='email'` by readers (workflow builder, sequence
--  enrolment, dispatch). No data backfill required because:
--    1. Old campaigns predate LinkedIn V3 entirely.
--    2. The application code reads NULL as 'email' explicitly.
--
--  Idempotency: re-runnable.
--
--  Verify (after apply):
--    \d campaigns                                        -- channel_strategy column visible
--    SELECT pg_get_constraintdef(oid)
--      FROM pg_constraint
--     WHERE conname = 'campaigns_channel_strategy_check'; -- CHECK present
--
--  Rollback:
--    ALTER TABLE public.campaigns
--      DROP CONSTRAINT IF EXISTS campaigns_channel_strategy_check;
--    ALTER TABLE public.campaigns
--      DROP COLUMN IF EXISTS channel_strategy;
-- ============================================================

ALTER TABLE public.campaigns
  ADD COLUMN IF NOT EXISTS channel_strategy TEXT;

-- CHECK constraint via DO block so re-runs don't fail. Postgres won't
-- silently swallow `IF NOT EXISTS` on constraints, so we look it up.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
      FROM pg_constraint
     WHERE conname = 'campaigns_channel_strategy_check'
  ) THEN
    ALTER TABLE public.campaigns
      ADD CONSTRAINT campaigns_channel_strategy_check
      CHECK (channel_strategy IS NULL
             OR channel_strategy IN ('linkedin', 'email', 'mixed'));
  END IF;
END $$;

COMMENT ON COLUMN public.campaigns.channel_strategy IS
  'V3 LinkedIn integration. NULL = legacy / treated as ''email'' by readers. Set explicitly by the campaign-create wizard. Drives workflow palette filtering (see CampaignWorkflowBuilder), sequence enrolment routing, and reply-pause cross-channel logic.';

-- Index helps any "list LinkedIn-only campaigns for this org" query.
-- Partial — most rows are email/null and don't need indexing.
CREATE INDEX IF NOT EXISTS idx_campaigns_channel_strategy_linkedin
  ON public.campaigns(organization_id)
  WHERE channel_strategy = 'linkedin';

NOTIFY pgrst, 'reload schema';
