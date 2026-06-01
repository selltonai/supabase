-- ============================================================
--  Migration: 249_create_campaign_sequence_actions
--  Date:      2026-05-05
--  Author:    Sellton AI — LinkedIn integration V3 / Phase B
--  Plan ref:  /Ground Truth/LINKEDIN_INTEGRATION_EXECUTION_PLAN_V3.md  §6.5, §13
--  Build log: /Ground Truth/LINKEDIN_V3_BUILD_LOG.md  §4 → Phase B
--  Depends:   248_create_campaign_contacts.sql
-- ============================================================
--
--  Purpose
--  -------
--  Channel-agnostic action ledger. One row per planned/in-flight/done
--  action, regardless of channel:
--
--    • LinkedIn invite
--    • LinkedIn message
--    • Email send (future, when campaign_emails converges here)
--    • Cross-channel fallback step
--
--  This is the Modal worker's "claim surface" (V3 §13.2). The worker:
--
--    1. SELECTs `WHERE status='pending' AND scheduled_at <= NOW()` with
--       a row-level lock or atomic status-flip to 'ready_for_review'.
--    2. Creates a review_draft task.
--    3. On approval, executes via the provider adapter.
--    4. Writes back `executed_at` + status='executed' + the linked
--       artifact id (linkedin_action_log_id, linkedin_message_id, etc.).
--
--  Why a separate table from review_draft tasks
--  --------------------------------------------
--  A review task exists only AFTER the worker decides the step is due.
--  A sequence action exists from the moment it's PLANNED. The action
--  row is what the worker claims and reschedules; the task row is the
--  human-facing surface that may or may not be created depending on
--  state. Keeping them separate also lets us record cancelled or
--  skipped steps (which never produced a task at all).
--
--  Linking columns explained
--  -------------------------
--    review_task_id           — UUID of the tasks row (when one exists)
--    campaign_email_id        — UUID of the campaign_emails row (email steps)
--    linkedin_action_log_id   — UUID of the linkedin_action_log row
--                                 (set after a successful Unipile call)
--    linkedin_message_id      — UUID of the linkedin_messages row when
--                                 the action produced a stored outbound
--                                 message
--
--  All four are nullable. A given action will populate one or more
--  depending on channel and lifecycle state. No FKs because the target
--  tables are mixed-ownership (some Sellton-managed, some not).
--
--  Idempotency: re-runnable.
--
--  Verify (after apply):
--    SELECT * FROM campaign_sequence_actions LIMIT 0;                                  -- columns load
--    SELECT relrowsecurity FROM pg_class WHERE relname='campaign_sequence_actions';    -- t
--    SELECT count(*) FROM pg_indexes WHERE tablename='campaign_sequence_actions';      -- 4 (PK + 3)
--
--  Rollback: DROP TABLE IF EXISTS public.campaign_sequence_actions CASCADE;
-- ============================================================


CREATE TABLE IF NOT EXISTS public.campaign_sequence_actions (
  id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Parent journey. ON DELETE CASCADE is intentional: if the journey is
  -- deleted (e.g. campaign deleted, user purged), the planned actions
  -- below it are no longer meaningful. Audit lives in
  -- linkedin_action_log / provider_event_log, both of which intentionally
  -- have NO cascade.
  campaign_contact_id      UUID NOT NULL
                           REFERENCES public.campaign_contacts(id)
                           ON DELETE CASCADE,

  -- Channel + action type. Channel is what the action runs against;
  -- action_type is the kind of operation. Both string-typed with CHECK
  -- so the enum is expandable via follow-up migration.
  channel                  TEXT NOT NULL
                           CHECK (channel IN ('linkedin', 'email')),
  action_type              TEXT NOT NULL
                           CHECK (action_type IN (
                             -- LinkedIn-specific
                             'linkedin_invitation',
                             'linkedin_message',
                             'linkedin_followup',
                             -- Email-specific (placeholder; email path
                             -- still lives in campaign_emails for v1)
                             'email_send'
                           )),

  -- Lifecycle. Worker claim flips pending → ready_for_review (atomic).
  -- Approval flips ready_for_review → approved. Execution flips
  -- approved → executed (or → failed). User cancellation lands as
  -- cancelled. Skipped is for journeys where the step is no longer
  -- relevant (e.g. counterpart already replied — no need to send).
  status                   TEXT NOT NULL DEFAULT 'pending'
                           CHECK (status IN (
                             'pending',
                             'ready_for_review',
                             'approved',
                             'executed',
                             'cancelled',
                             'failed',
                             'skipped'
                           )),

  -- Schedule. NULL means "as soon as the worker can pick it up";
  -- a future timestamp pauses until then.
  scheduled_at             TIMESTAMPTZ,

  -- Outcome timestamps + linkings (all nullable).
  executed_at              TIMESTAMPTZ,
  review_task_id           UUID,                    -- soft ref → tasks
  campaign_email_id        UUID,                    -- soft ref → campaign_emails (email channel)
  linkedin_action_log_id   UUID,                    -- soft ref → linkedin_action_log
  linkedin_message_id      UUID,                    -- soft ref → linkedin_messages

  -- Free-form per-action metadata (e.g. last_error, retry_count, draft_copy).
  metadata                 JSONB NOT NULL DEFAULT '{}'::jsonb,

  created_at               TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at               TIMESTAMPTZ NOT NULL DEFAULT NOW()
);


-- ============================================================
--  INDEXES — claim hot path + dashboard reads
-- ============================================================

-- Worker claim: "pending actions whose scheduled_at has arrived". This
-- is the most-hit query in the system once orchestration is live. Partial
-- index keeps cost low even at scale.
CREATE INDEX IF NOT EXISTS idx_campaign_sequence_actions_due
  ON public.campaign_sequence_actions(status, scheduled_at)
  WHERE status = 'pending';

-- Per-journey lookup ("show all actions for this contact in this campaign").
CREATE INDEX IF NOT EXISTS idx_campaign_sequence_actions_journey
  ON public.campaign_sequence_actions(campaign_contact_id, status);

-- Task ↔ action lookup. When a review task is approved/cancelled, the
-- handler needs to find the underlying action row by review_task_id.
CREATE INDEX IF NOT EXISTS idx_campaign_sequence_actions_task
  ON public.campaign_sequence_actions(review_task_id)
  WHERE review_task_id IS NOT NULL;


-- ============================================================
--  RLS
-- ============================================================

ALTER TABLE public.campaign_sequence_actions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS campaign_sequence_actions_org_select ON public.campaign_sequence_actions;

-- SELECT — must join through campaign_contacts to derive
-- organization_id. Use the join-via-EXISTS pattern so the policy
-- evaluates without exposing internal IDs unnecessarily.
CREATE POLICY campaign_sequence_actions_org_select
  ON public.campaign_sequence_actions
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.campaign_contacts cc
      WHERE cc.id = campaign_sequence_actions.campaign_contact_id
        AND cc.organization_id = (auth.jwt() ->> 'org_id')
    )
  );

-- INSERT/UPDATE/DELETE: BFF/worker only via service role.


-- ============================================================
--  COMMENTS
-- ============================================================

COMMENT ON TABLE public.campaign_sequence_actions IS
  'Channel-agnostic action ledger for the orchestration engine. Modal worker''s claim surface. V3 §6.5, §13.';

COMMENT ON COLUMN public.campaign_sequence_actions.action_type IS
  'V1 supported: linkedin_invitation, linkedin_message, linkedin_followup, email_send. New types require a CHECK migration. The full email_send path is gated on a later cycle when campaign_emails eventually converges; v1 mostly plans LinkedIn rows here and lets email continue running on campaign_emails directly.';

COMMENT ON COLUMN public.campaign_sequence_actions.status IS
  'Lifecycle: pending → ready_for_review → approved → executed. Branches: cancelled (user), skipped (journey-state change made step irrelevant), failed (provider error during execute). Never skip to executed without going through approved (V3 §11.3).';

COMMENT ON COLUMN public.campaign_sequence_actions.linkedin_action_log_id IS
  'Set when this action produced a row in linkedin_action_log (i.e. we made the Unipile API call). Soft reference — no FK because the audit log intentionally outlives this row.';

COMMENT ON COLUMN public.campaign_sequence_actions.review_task_id IS
  'Set when the worker created a review_draft task for human approval. NULL while the action is still in pending/cancelled/skipped without a task surface.';


NOTIFY pgrst, 'reload schema';
