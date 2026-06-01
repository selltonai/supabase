-- ============================================================
--  Migration: 269_sprint5_phasec_reply_drafts
--  Date:      2026-05-22
--  Author:    Sellton AI — Sprint 5 Phase C
--  Plan ref:  Ground Truth/specs/sprint-5-reply-handler.md Phase C
--             Ground Truth/OUTREACH_INTELLIGENCE_PLAN.md §8 (especially §8.4-8.6)
--             Ground Truth/ARI_ALIGNMENT.md §1.1 (no crm_* prefix; unprefixed name)
-- ============================================================
--
--  Purpose
--  -------
--  Sprint 5 Phase C — creates the `reply_drafts` table that stores
--  drafted replies produced by ReplyHandlerService.draft_step() (Sonnet
--  via chat_completion_structured) for inbound messages.
--
--  Why a separate table (not just tasks.body)
--  -------------------------------------------
--  Tasks have a lifecycle (pending → completed) that's distinct from
--  draft revisions. An operator may regenerate a draft multiple times
--  before approving; tasks.body can't hold draft history. reply_drafts
--  is the operator-edit surface; tasks.body holds the snapshot at
--  surfacing time. Sprint 5 #1 spec §6 Arg 3 captures this rationale.
--
--  Polymorphic message reference (Option A — single column + channel)
--  ------------------------------------------------------------------
--  message_id is a polymorphic foreign reference (no FK enforced).
--  channel column says which table it points at:
--    channel='linkedin' → message_id ∈ linkedin_messages.id
--    channel='email'    → message_id ∈ campaign_emails.id
--  Cleaner relational design (split columns + CHECK constraint) is a
--  refactor for later if FK enforcement becomes critical. For v1, the
--  application layer (ReplyHandlerService) is the single writer and
--  enforces consistency.
--
--  Status lifecycle
--  ----------------
--  draft     → drafter completed; operator may edit, approve, or reject
--  approved  → operator approved (manually or via autopilot); awaits send
--  sent      → channel dispatcher confirmed delivery
--  rejected  → operator explicitly rejected; no send attempt
--  failed    → drafter or dispatcher failed unrecoverably
--
--  task_id linkage
--  ---------------
--  reply_drafts.task_id references the review_reply task created
--  alongside the draft (Sprint 5 #1 spec §4.5). The task surfaces
--  the draft to operators; the reply_drafts row holds the structured
--  draft + KB asset + classifier snapshot for audit/regenerate.
--
--  ARI alignment
--  -------------
--  ARI Stream 9 reply_handler agent has equivalent surface; the
--  reply_drafts table carries forward 1:1 to ARI's schema. Per
--  ARI_ALIGNMENT.md §1.1 no crm_* prefix — unprefixed name matches
--  Sellton convention.
--
--  Idempotency
--  -----------
--  All operations use IF NOT EXISTS — safe to re-apply.
--
--  Pre-apply verification (operator runs in Supabase Studio)
--  ----------------------------------------------------------
--    SELECT to_regclass('public.reply_drafts');
--    -- Expected (pre-apply): NULL
--
--    -- Confirm task_type ENUM has 'review_reply' (migration 268)
--    SELECT 'review_reply' = ANY(enum_range(NULL::task_type)) AS has_review_reply;
--    -- Expected: TRUE — gates Sprint 5 Phase C; if FALSE, apply 268 first
--
--  Post-apply verification
--  -----------------------
--    SELECT to_regclass('public.reply_drafts');
--    -- Expected: 'public.reply_drafts'
--
--    SELECT column_name, data_type
--    FROM information_schema.columns
--    WHERE table_schema = 'public' AND table_name = 'reply_drafts'
--    ORDER BY ordinal_position;
--    -- Expected: 18 rows including id, organization_id, message_id, channel,
--    --          contact_id, campaign_id, drafted_body, drafted_subject,
--    --          suggested_action, kb_asset_used, classification_snapshot,
--    --          drafter_metadata, status, task_id, created_at, updated_at,
--    --          approved_at, approved_by_user_id, sent_at, error, error_detail
--
--    SELECT indexname FROM pg_indexes
--    WHERE tablename = 'reply_drafts'
--    ORDER BY indexname;
--    -- Expected: 3 indexes (org_created, message, pending_drafts)
--
--  Rollback
--  --------
--    DROP TABLE IF EXISTS public.reply_drafts;
--  Safe — no FKs from other tables reference reply_drafts in Phase C.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.reply_drafts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id TEXT NOT NULL,
  -- Polymorphic message reference (per `channel` column).
  -- channel='linkedin' → message_id is linkedin_messages.id
  -- channel='email'    → message_id is campaign_emails.id
  message_id UUID NOT NULL,
  channel TEXT NOT NULL CHECK (channel IN ('linkedin', 'email')),
  -- Optional context (may be NULL — webhook may not resolve them).
  contact_id UUID NULL,
  campaign_id UUID NULL,
  -- Drafter output.
  drafted_body TEXT NOT NULL,
  drafted_subject TEXT NULL,  -- email only (LinkedIn has no subject)
  suggested_action TEXT NOT NULL DEFAULT 'send'
    CHECK (suggested_action IN ('send', 'send_with_calendar_invite', 'send_with_attachment', 'route_to_human', 'mark_as_lost')),
  -- Audit + regenerate fuel.
  kb_asset_used JSONB NULL,  -- snapshot of the KB asset the drafter grounded on
  classification_snapshot JSONB NULL,  -- intent/sub_intent/confidence at draft time
  drafter_metadata JSONB NOT NULL DEFAULT '{}'::jsonb,  -- model, tokens, confidence, reasoning_note
  -- Lifecycle.
  status TEXT NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft', 'approved', 'sent', 'rejected', 'failed')),
  -- Linkage to the review_reply task surfacing this draft.
  task_id UUID NULL,
  -- Timestamps + approval audit.
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  approved_at TIMESTAMPTZ NULL,
  approved_by_user_id TEXT NULL,
  sent_at TIMESTAMPTZ NULL,
  -- Failure surface.
  error TEXT NULL,
  error_detail TEXT NULL
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_reply_drafts_org_created
  ON public.reply_drafts (organization_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_reply_drafts_message
  ON public.reply_drafts (message_id, channel);

-- Partial index for the "pending operator approval" queue —
-- shrinks naturally as drafts get approved/rejected.
CREATE INDEX IF NOT EXISTS idx_reply_drafts_pending
  ON public.reply_drafts (organization_id, created_at DESC)
  WHERE status = 'draft';

-- Column documentation
COMMENT ON TABLE public.reply_drafts IS
  'Sprint 5 Phase C — drafts produced by ReplyHandlerService.draft_step() for inbound messages. Polymorphic via channel column. Has its own lifecycle (draft → approved → sent | rejected | failed) distinct from the review_reply task lifecycle.';

COMMENT ON COLUMN public.reply_drafts.message_id IS
  'Polymorphic — references linkedin_messages.id when channel=linkedin, campaign_emails.id when channel=email. No FK enforced (split columns + CHECK is a refactor for later if needed).';

COMMENT ON COLUMN public.reply_drafts.channel IS
  'linkedin | email. Determines which message table message_id points to + which voice the drafter used (sender_voice for linkedin, brand_voice for email).';

COMMENT ON COLUMN public.reply_drafts.suggested_action IS
  'Drafter''s suggestion: send | send_with_calendar_invite | send_with_attachment | route_to_human | mark_as_lost. Operator may override; this is the drafter recommendation only.';

COMMENT ON COLUMN public.reply_drafts.kb_asset_used IS
  'Snapshot of the KB asset (chunk + score + metadata) the drafter grounded on. NULL when no KB asset was relevant (drafted from campaign goal directly). Used by audit + regenerate flows.';

COMMENT ON COLUMN public.reply_drafts.classification_snapshot IS
  'Intent classifier output at draft time. Captured so operators can see the WHY behind a draft even after the linkedin_messages.classification column gets re-classified.';

COMMENT ON COLUMN public.reply_drafts.drafter_metadata IS
  'Sonnet model + token counts + drafter confidence + reasoning_note. Default empty object for forward compatibility.';

COMMENT ON COLUMN public.reply_drafts.status IS
  'draft (initial) | approved (operator or autopilot) | sent (dispatcher confirmed) | rejected (operator no-go) | failed (drafter or dispatcher unrecoverable).';

COMMENT ON COLUMN public.reply_drafts.task_id IS
  'Linked tasks.id (task_type=review_reply) that surfaces this draft to operators. NULL temporarily during initial insert; populated by handle_reply after task insert.';

COMMENT ON INDEX public.idx_reply_drafts_pending IS
  'Sprint 5 — Partial index supporting the "pending operator approval" queue. Shrinks as drafts transition out of status=draft.';
