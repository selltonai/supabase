-- ============================================================
--  Migration: 270_sprint5_autopilot_reply_gate
--  Date:      2026-05-22
--  Author:    Sellton AI — Sprint 5 Autopilot Extension (§11 source plan)
--  Plan ref:  Ground Truth/specs/sprint-5-autopilot-extension.md
--             Ground Truth/OUTREACH_INTELLIGENCE_PLAN.md §11.2
--             Ground Truth/OUTREACH_INTELLIGENCE_OPEN_QUESTIONS_RESOLUTION.md Q3+Q6
-- ============================================================
--
--  Purpose
--  -------
--  Sprint 5 autopilot extension. Adds 4 new columns to the existing
--  campaigns.autopilot_* family (migrations 216/219/255) that gate when
--  a Sprint 5 Phase C drafter output auto-sends vs surfaces as a
--  review_reply task. Per source plan §11 — "extend, don't rebuild."
--
--  4 new columns:
--
--   1. autopilot_allowed_intent_classes TEXT[] DEFAULT '{ooo}'
--      Which classifier intents are eligible for auto-send. Default
--      contains only 'ooo' (out-of-office auto-replies — lowest risk).
--      UI exposes 4 toggleable: ooo, question, positive_intent, referral.
--      Other intents (objection, not_interested, unsubscribe, unclear)
--      stay non-autopilotable — they're high-risk or have sequence-engine
--      actions (Phase D #3), not drafts.
--
--   2. autopilot_min_classifier_confidence NUMERIC(3,2) DEFAULT 0.90
--      Classifier confidence floor. Drafts where classifier.confidence
--      < this value surface as tasks regardless of intent allowlist.
--      Default 0.90 is conservative — avoids low-confidence auto-sends.
--      CHECK constraint enforces 0-1 range.
--
--   3. autopilot_brand_voice_compliance_required BOOLEAN DEFAULT FALSE
--      Q3 DEVIATION from source plan. Source plan defaults TRUE; Q3
--      recommends FALSE for first 14 days while BrandVoiceComplianceCheck
--      accuracy data is collected. Operator flips TRUE only if
--      false-negative rate < 5% per telemetry. Applies to email auto-send
--      only (Sprint 6 territory; LinkedIn doesn't use brand voice check).
--
--   4. autopilot_auto_confirm_linkedin_replies BOOLEAN DEFAULT FALSE
--      Master switch for LinkedIn reply autopilot. Mirrors the existing
--      autopilot_auto_confirm_reply_emails column from migration 219
--      for email. Default FALSE so day-1 has zero auto-sends — every
--      reply surfaces as a task for manual review.
--
--  Day-1 behavior under defaults (ALL safe):
--   - autopilot_auto_confirm_linkedin_replies = FALSE → all replies → tasks
--   - autopilot_auto_confirm_reply_emails = FALSE (existing) → same for email
--   - Even if operator flips master switches: only 'ooo' intent in allowlist
--   - Even if intent allowlist expanded: 0.90 confidence floor blocks low-conf
--   - Brand voice check disabled for 14 days (Q3); no false-negative blocks
--
--  Idempotency
--  -----------
--  All ADD COLUMN use IF NOT EXISTS. CHECK constraint uses ADD CONSTRAINT
--  with IF NOT EXISTS pattern (Postgres 14+ — falls through to DO block
--  for portability).
--
--  Pre-apply verification (operator runs in Supabase Studio)
--  ---------------------------------------------------------
--    SELECT column_name FROM information_schema.columns
--    WHERE table_name = 'campaigns'
--      AND column_name IN (
--        'autopilot_allowed_intent_classes',
--        'autopilot_min_classifier_confidence',
--        'autopilot_brand_voice_compliance_required',
--        'autopilot_auto_confirm_linkedin_replies'
--      );
--    -- Expected (pre-apply): 0 rows
--
--  Post-apply verification
--  -----------------------
--    SELECT column_name, data_type, column_default FROM information_schema.columns
--    WHERE table_name = 'campaigns'
--      AND column_name IN (
--        'autopilot_allowed_intent_classes',
--        'autopilot_min_classifier_confidence',
--        'autopilot_brand_voice_compliance_required',
--        'autopilot_auto_confirm_linkedin_replies'
--      ) ORDER BY column_name;
--    -- Expected: 4 rows with documented defaults
--
--    SELECT autopilot_allowed_intent_classes,
--           autopilot_min_classifier_confidence,
--           autopilot_brand_voice_compliance_required,
--           autopilot_auto_confirm_linkedin_replies
--    FROM campaigns LIMIT 1;
--    -- Expected: {ooo}, 0.90, false, false
--
--    SELECT conname FROM pg_constraint
--    WHERE conrelid = 'public.campaigns'::regclass
--      AND conname = 'chk_autopilot_min_classifier_confidence_range';
--    -- Expected: 1 row
--
--  Rollback (safe; columns + constraint are additive)
--  ---------------------------------------------------
--    ALTER TABLE public.campaigns
--      DROP CONSTRAINT IF EXISTS chk_autopilot_min_classifier_confidence_range,
--      DROP COLUMN IF EXISTS autopilot_allowed_intent_classes,
--      DROP COLUMN IF EXISTS autopilot_min_classifier_confidence,
--      DROP COLUMN IF EXISTS autopilot_brand_voice_compliance_required,
--      DROP COLUMN IF EXISTS autopilot_auto_confirm_linkedin_replies;
--
--  ARI alignment
--  -------------
--  Feeds Stream 11 (User Mgmt & Billing) autopilot policy engine. The
--  4 columns + the autopilot_should_send() gate logic carry forward 1:1
--  to ARI's policy engine — same column names, same defaults, same gate
--  semantics. Per ARI_ALIGNMENT.md §1.1 unprefixed convention.
-- ============================================================

ALTER TABLE public.campaigns
  ADD COLUMN IF NOT EXISTS autopilot_allowed_intent_classes TEXT[] NOT NULL DEFAULT '{ooo}',
  ADD COLUMN IF NOT EXISTS autopilot_min_classifier_confidence NUMERIC(3,2) NOT NULL DEFAULT 0.90,
  -- Q3 deviation: default FALSE for first 14 days; operator flips TRUE only
  -- if BrandVoiceComplianceCheck false-negative rate < 5% per telemetry.
  ADD COLUMN IF NOT EXISTS autopilot_brand_voice_compliance_required BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS autopilot_auto_confirm_linkedin_replies BOOLEAN NOT NULL DEFAULT FALSE;

-- CHECK constraint on confidence range (idempotent via DO block since
-- Postgres < 14 doesn't support ADD CONSTRAINT IF NOT EXISTS).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.campaigns'::regclass
      AND conname = 'chk_autopilot_min_classifier_confidence_range'
  ) THEN
    ALTER TABLE public.campaigns
      ADD CONSTRAINT chk_autopilot_min_classifier_confidence_range
      CHECK (
        autopilot_min_classifier_confidence >= 0
        AND autopilot_min_classifier_confidence <= 1
      );
  END IF;
END $$;

-- Column documentation
COMMENT ON COLUMN public.campaigns.autopilot_allowed_intent_classes IS
  'Sprint 5 §11 — Which classifier intents are eligible for auto-send (subset of {ooo, question, positive_intent, referral}). Default {ooo} only — safest. Operator opt-in expansion via UI. Other intents (objection, not_interested, unsubscribe, unclear) stay non-autopilotable.';

COMMENT ON COLUMN public.campaigns.autopilot_min_classifier_confidence IS
  'Sprint 5 §11 — Floor for classifier.confidence to be eligible for auto-send. Default 0.90 (conservative). CHECK constraint enforces 0-1 range. Drafts below threshold surface as tasks regardless of intent allowlist.';

COMMENT ON COLUMN public.campaigns.autopilot_brand_voice_compliance_required IS
  'Sprint 5 §11 — When TRUE, Modal runs BrandVoiceComplianceCheck (Haiku) before email auto-send; drafts that conflict with brand voice surface as tasks. Default FALSE for first 14 days per Resolution Q3 (deviation from source plan default-TRUE) — operator flips TRUE only when compliance check false-negative rate < 5% per telemetry data. Applies to email auto-send only (Sprint 6).';

COMMENT ON COLUMN public.campaigns.autopilot_auto_confirm_linkedin_replies IS
  'Sprint 5 §11 — Master switch for LinkedIn reply autopilot. Mirrors autopilot_auto_confirm_reply_emails (migration 219) for email. Default FALSE — every reply surfaces as task. Operator flips per-campaign to opt into autopilot for that campaign''s LinkedIn replies (still subject to intent allowlist + confidence threshold).';

COMMENT ON CONSTRAINT chk_autopilot_min_classifier_confidence_range ON public.campaigns IS
  'Sprint 5 §11 — Ensures autopilot_min_classifier_confidence stays in valid probability range [0, 1].';
