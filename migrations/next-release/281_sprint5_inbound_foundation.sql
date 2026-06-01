-- ============================================================
--  Migration: 268_sprint5_inbound_foundation
--  Date:      2026-05-22
--  Author:    Sellton AI — Sprint 5 Phase A foundation
--  Plan ref:  Ground Truth/specs/sprint-5-reply-handler.md §4.1
--             Ground Truth/OUTREACH_INTELLIGENCE_PLAN.md §8 + §11.2
-- ============================================================
--
--  Purpose
--  -------
--  Sprint 5 Phase A foundations — schema-only changes that unblock the
--  upcoming `ReplyHandlerService` (Phase B) and `reply_drafts` work
--  (Phase C). Three concerns in one migration since they're tightly
--  coupled and ship together:
--
--   1. ALTER TYPE task_type ADD VALUE 'review_reply'
--      - Existing 4 values: review_draft, meeting, company_verification,
--        email_generation_processing (verified via QA on 2026-05-21).
--      - Sprint 5 Phase C will create review_reply tasks; the ENUM value
--        must exist BEFORE any INSERT can write it.
--      - The BFF `validTaskTypes` array (selltonai/src/app/api/tasks/route.ts:144)
--        gets a coordinated update in the same Phase A batch (separate
--        commit) to:
--          - Drop dead values not in ENUM: 'send_email', 'follow_up', 'custom'
--            (these would crash INSERT — pre-existing tech-debt #23).
--          - Add 'review_reply' to match the new ENUM value.
--      - ALTER TYPE ... ADD VALUE is non-transactional in older Postgres
--        but safe with IF NOT EXISTS guard (Postgres 12+, which Supabase
--        runs).
--
--   2. linkedin_messages.classification JSONB
--      - Stores ReplyClassifier output per inbound LinkedIn message.
--      - Shape (Phase B writes):
--          {
--            "intent": "<one of 8>",       -- positive_intent | question | objection |
--                                          -- referral | not_interested | unsubscribe |
--                                          -- ooo | unclear
--            "sub_intent": "<sub|null>",   -- intent-specific sub-classes (pricing,
--                                          -- timing, fit, competitor, already_solved,
--                                          -- about_product, about_pricing, about_fit,
--                                          -- general — see plan §8.2)
--            "confidence": 0.0-1.0,
--            "urgency": "high|medium|low",
--            "extracted_entities": {...} | null,
--            "reasoning": "1-sentence why",
--            "classified_at": "<ISO timestamp>",
--            "model_used": "claude-haiku-4-5",
--            "tokens_used": <int>,
--            "error": null               -- non-null on classifier failure
--          }
--      - NULL means not classified yet (outbound message, or pre-Sprint-5
--        inbound message that the classifier hasn't backfilled).
--      - No provenance wrapper here (unlike contacts.linkedin_signals)
--        because the classifier is single-source single-pass. Provenance
--        wrapping is reserved for multi-source merge scenarios.
--
--   3. campaign_emails.classification JSONB
--      - Same shape as linkedin_messages.classification.
--      - Used by the email-side wiring in Sprint 6 (gmail-api queue →
--        BFF classify-and-draft route).
--      - Adding the column now (with the LinkedIn one) avoids two
--        migrations + keeps the inbound brain unified across channels.
--
--   4. Partial indexes idx_*_classified
--      - Support per-org analytics queries that filter on "messages
--        classified in last N days." Partial WHERE classification IS
--        NOT NULL keeps the indexes small (classification fills in
--        over time as inbound arrives, not on every row).
--
--  Idempotency
--  -----------
--  - ALTER TYPE ... ADD VALUE uses IF NOT EXISTS — safe to re-apply.
--  - ADD COLUMN uses IF NOT EXISTS — safe to re-apply.
--  - CREATE INDEX uses IF NOT EXISTS — safe to re-apply.
--
--  Pre-apply verification
--  ----------------------
--    -- Confirm existing ENUM values (verify nothing has changed since
--    -- this migration was written)
--    SELECT enumlabel FROM pg_enum
--    WHERE enumtypid = 'task_type'::regtype
--    ORDER BY enumsortorder;
--    -- Expected (pre-apply): review_draft, meeting, company_verification,
--    --                       email_generation_processing
--
--    -- Confirm classification columns don't already exist
--    SELECT table_name, column_name FROM information_schema.columns
--    WHERE table_name IN ('linkedin_messages', 'campaign_emails')
--      AND column_name = 'classification';
--    -- Expected (pre-apply): 0 rows
--
--  Post-apply verification
--  -----------------------
--    SELECT enumlabel FROM pg_enum
--    WHERE enumtypid = 'task_type'::regtype
--    ORDER BY enumsortorder;
--    -- Expected: 5 values, ending with review_reply
--
--    SELECT table_name, column_name, data_type FROM information_schema.columns
--    WHERE table_name IN ('linkedin_messages', 'campaign_emails')
--      AND column_name = 'classification';
--    -- Expected: 2 rows, both jsonb
--
--    SELECT indexname FROM pg_indexes
--    WHERE indexname IN ('idx_linkedin_messages_classified',
--                        'idx_campaign_emails_classified');
--    -- Expected: 2 rows
--
--  Rollback
--  --------
--  - Columns + indexes: safe to drop (no consumers in Phase A).
--      DROP INDEX IF EXISTS public.idx_linkedin_messages_classified;
--      DROP INDEX IF EXISTS public.idx_campaign_emails_classified;
--      ALTER TABLE public.linkedin_messages DROP COLUMN IF EXISTS classification;
--      ALTER TABLE public.campaign_emails DROP COLUMN IF EXISTS classification;
--  - ENUM value: Postgres does NOT support dropping ENUM values. Acceptable —
--    the value is forward-only addition; nothing consumes it until Phase C.
--    If absolutely needed, the workaround is ENUM recreation:
--      CREATE TYPE task_type_new AS ENUM (...4 original values...);
--      ALTER TABLE tasks ALTER COLUMN task_type TYPE task_type_new USING task_type::text::task_type_new;
--      DROP TYPE task_type;
--      ALTER TYPE task_type_new RENAME TO task_type;
--    This is destructive — only do it if review_reply was never used.
--
--  ARI alignment
--  -------------
--  Feeds ARI Stream 9 (Agent Implementation) reply_handler agent +
--  Stream 8 (Inbound Leads). Both classification columns + the ENUM
--  value are required by ARI's `linkedin_intent_collector` and
--  `reply_handler` agents. JSONB shape per the canonical structure
--  documented in this file's header comments — carries forward 1:1 to
--  ARI's classification table or stays as JSONB on a renamed table
--  depending on Stream 8/9 design at cutover.
-- ============================================================

-- 1. ENUM extension
ALTER TYPE task_type ADD VALUE IF NOT EXISTS 'review_reply';

-- 2. Classification columns on inbound message tables
ALTER TABLE public.linkedin_messages
  ADD COLUMN IF NOT EXISTS classification JSONB;

ALTER TABLE public.campaign_emails
  ADD COLUMN IF NOT EXISTS classification JSONB;

-- 3. Partial indexes for analytics filters
CREATE INDEX IF NOT EXISTS idx_linkedin_messages_classified
  ON public.linkedin_messages (organization_id, occurred_at DESC)
  WHERE classification IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_campaign_emails_classified
  ON public.campaign_emails (organization_id, sent_at DESC)
  WHERE classification IS NOT NULL;

-- 4. Column documentation
COMMENT ON COLUMN public.linkedin_messages.classification IS
  'Sprint 5 — Reply classifier output. Shape: {intent, sub_intent, confidence, urgency, extracted_entities, reasoning, classified_at, model_used, tokens_used, error}. NULL means not classified yet (outbound or pre-Sprint-5 inbound). Written by ReplyHandlerService.classify_step (Modal). Read by review_reply task creation (Sprint 5 Phase C).';

COMMENT ON COLUMN public.campaign_emails.classification IS
  'Sprint 5 — Same shape as linkedin_messages.classification, for inbound email replies. Written when Sprint 6 wires gmail-api queue → BFF classify-and-draft route.';

COMMENT ON INDEX public.idx_linkedin_messages_classified IS
  'Sprint 5 — Partial index for analytics queries filtering on "messages classified in last N days." Shrinks naturally as inbound arrives.';

COMMENT ON INDEX public.idx_campaign_emails_classified IS
  'Sprint 5 — Same partial index pattern for campaign_emails.';
