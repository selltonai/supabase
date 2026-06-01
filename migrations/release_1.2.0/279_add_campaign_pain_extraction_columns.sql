-- ============================================================
--  Migration: 266_add_campaign_pain_extraction_columns
--  Date:      2026-05-13
--  Author:    Sellton AI — Outreach Intelligence Sprint 2 Commit #2
--  Plan ref:  Ground Truth/EMAIL_WRITING_IMPROVEMENT_PLAN.md §3
--             Ground Truth/CAMPAIGN_CREATION_UI_PLAN.md §3.2
--             Ground Truth/OUTREACH_INTELLIGENCE_STATE_AND_FORWARD_PLAN.md §3
-- ============================================================
--
--  Purpose
--  -------
--  Add columns to the `campaigns` table for storing the result of pain
--  extraction (Sprint 2 Commit #3 ships the extraction service itself).
--
--  Pain extraction reads `description` (CTA + goal) + `product_description`
--  (pain + solution) as SEPARATE signals (per Resolution Q14) and produces:
--
--    1. A 3-4 sentence pain_statement that summarizes the core
--       operational problem the product solves.
--    2. target_signals — observable patterns in research that suggest
--       a prospect company has this pain.
--    3. irrelevant_signals — things that look interesting but don't
--       indicate this pain (so the email distillation service in Sprint 3
--       can explicitly discard them).
--    4. extraction_warnings — model-detected contradictions between
--       the two source fields (e.g., goal says "SaaS companies",
--       product says "finance teams" — flag the misalignment so the
--       operator can revise the brief).
--
--  These columns are READ by Sprint 3's EmailDistillationService when
--  selecting per-contact angles, AND by Sprint 4's LinkedIn writer.
--
--  Why JSONB for signal arrays
--  ---------------------------
--  Each signal is a short string ("scaling sales team past 20 reps",
--  "Series B stage", etc.). A TEXT[] column would work but JSONB:
--    - Supports future enrichment (e.g., signal_strength scores)
--    - Matches the existing pattern (campaigns.b2b_search_filters JSONB,
--      contacts.linkedin_profile JSONB, etc.)
--    - Enables GIN-index queries when we want to filter campaigns by
--      target signals later (e.g., "show campaigns targeting SaaS")
--
--  Default '[]'::jsonb (empty array, not NULL) so downstream consumers
--  can iterate without null-checking. Null would only occur for legacy
--  campaigns where extraction has never been attempted — they get the
--  default '[]' on this migration's apply.
--
--  Why pain_extraction_model TEXT
--  ------------------------------
--  Track which model produced the extraction so we can detect when an
--  upgrade (e.g., Sonnet 4.6 → 5.0) is needed. Sprint 3's distillation
--  service can check `pain_extraction_model` against the current
--  recommended model and re-extract if stale.
--
--  Why partial index on pain_extracted_at IS NULL
--  ----------------------------------------------
--  Sprint 2 Commit #4 ships a cascade trigger that fires extraction on
--  every campaign save. But a backfill is needed for the ~545 existing
--  campaigns in stage (per Modal cron summary 2026-05-13). The partial
--  index makes the backfill query fast:
--
--    SELECT id FROM campaigns
--    WHERE pain_extracted_at IS NULL
--      AND (description IS NOT NULL OR product_description IS NOT NULL)
--    ORDER BY created_at DESC
--    LIMIT 50;
--
--  The index is small (only covers rows that haven't been extracted
--  yet, which shrinks to zero over time). Partial-where keeps it
--  lean. Drops naturally when backfill completes.
--
--  Idempotency
--  -----------
--  Uses `ADD COLUMN IF NOT EXISTS` so re-running is safe. The partial
--  index uses `CREATE INDEX IF NOT EXISTS`.
--
--  Pre-apply check (verifies the campaigns table exists + we won't
--  collide with existing columns):
--
--    SELECT column_name
--    FROM information_schema.columns
--    WHERE table_name = 'campaigns'
--      AND column_name IN (
--        'pain_statement',
--        'target_signals',
--        'irrelevant_signals',
--        'pain_extracted_at',
--        'extraction_warnings',
--        'pain_extraction_model'
--      );
--    -- Expected: 0 rows (none of these columns exist yet)
--    -- If non-empty, those columns are already present — the
--    -- IF NOT EXISTS guards make re-apply safe.
--
--  Post-apply verification:
--
--    SELECT column_name, data_type, column_default
--    FROM information_schema.columns
--    WHERE table_name = 'campaigns'
--      AND column_name IN (
--        'pain_statement',
--        'target_signals',
--        'irrelevant_signals',
--        'pain_extracted_at',
--        'extraction_warnings',
--        'pain_extraction_model'
--      )
--    ORDER BY column_name;
--    -- Expected: 6 rows with correct data_types
--
--    SELECT indexname FROM pg_indexes
--    WHERE tablename = 'campaigns'
--      AND indexname = 'idx_campaigns_pain_extraction_pending';
--    -- Expected: 1 row
--
--  Rollback (safe; columns and index are additive):
--
--    DROP INDEX IF EXISTS public.idx_campaigns_pain_extraction_pending;
--    ALTER TABLE public.campaigns
--      DROP COLUMN IF EXISTS pain_statement,
--      DROP COLUMN IF EXISTS target_signals,
--      DROP COLUMN IF EXISTS irrelevant_signals,
--      DROP COLUMN IF EXISTS pain_extracted_at,
--      DROP COLUMN IF EXISTS extraction_warnings,
--      DROP COLUMN IF EXISTS pain_extraction_model;
-- ============================================================

ALTER TABLE public.campaigns
  ADD COLUMN IF NOT EXISTS pain_statement TEXT,
  ADD COLUMN IF NOT EXISTS target_signals JSONB NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS irrelevant_signals JSONB NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS pain_extracted_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS extraction_warnings JSONB NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS pain_extraction_model TEXT;

-- Partial index for the backfill / re-extraction query.
-- WHERE clause keeps the index small as extraction completes campaign-by-campaign.
CREATE INDEX IF NOT EXISTS idx_campaigns_pain_extraction_pending
  ON public.campaigns (organization_id, created_at DESC)
  WHERE pain_extracted_at IS NULL;

-- Column documentation (visible in psql's \d+ and in many GUI tools).

COMMENT ON COLUMN public.campaigns.pain_statement IS
  'Sprint 2 (Outreach Intelligence) — 3-4 sentence operational pain statement extracted from campaign.description + campaign.product_description by CampaignPainExtractionService (Sonnet via AnthropicProvider tools+tool_choice). Drives angle selection in Sprint 3 EmailDistillationService and Sprint 4 LinkedIn writer. NULL means extraction has not been attempted (legacy campaigns) or failed (see extraction_warnings).';

COMMENT ON COLUMN public.campaigns.target_signals IS
  'Sprint 2 — JSONB array of strings. Observable signals in research/contact data that suggest a prospect has the pain. Read by EmailDistillationService when matching company research to the campaign pain. Example: ["scaling sales team past 20 reps", "Series B stage", "manual reconciliation process"]. Empty array means extraction has not run.';

COMMENT ON COLUMN public.campaigns.irrelevant_signals IS
  'Sprint 2 — JSONB array of strings. Signals that LOOK interesting in research but do NOT indicate this campaign''s pain. Explicitly listed so the distillation service can discard them. Example: ["new office opening", "award recognition", "funding news"]. Empty array means extraction has not run.';

COMMENT ON COLUMN public.campaigns.pain_extracted_at IS
  'Sprint 2 — Timestamp of the most recent SUCCESSFUL pain extraction. Updated by CampaignPainExtractionService. NULL means extraction has never succeeded for this campaign. Backed by partial index idx_campaigns_pain_extraction_pending for fast "needs extraction" queries.';

COMMENT ON COLUMN public.campaigns.extraction_warnings IS
  'Sprint 2 — JSONB array of strings. Model-detected issues during extraction, e.g., contradictions between description and product_description fields. Surfaced in the wizard UI so operators can revise. Empty array means clean extraction.';

COMMENT ON COLUMN public.campaigns.pain_extraction_model IS
  'Sprint 2 — Model identifier used for the extraction (e.g., "claude-sonnet-4-6"). Lets Sprint 3 detect stale extractions and trigger re-extraction when a recommended model upgrade lands.';

COMMENT ON INDEX public.idx_campaigns_pain_extraction_pending IS
  'Sprint 2 — Partial index supporting the backfill query for campaigns awaiting pain extraction. Shrinks naturally as extraction completes. See Sprint 2 Commit #4 cascade-trigger BFF route for the read-side query.';
