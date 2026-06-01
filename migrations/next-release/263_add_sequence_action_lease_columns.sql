-- ============================================================
--  Migration: 251_add_sequence_action_lease_columns
--  Date:      2026-05-06
--  Author:    Sellton AI — LinkedIn V3 / P1-1
--  Plan ref:  /Ground Truth/LINKEDIN_V3_EXECUTION_PLAN.md §3 P1-1
-- ============================================================
--
--  Purpose
--  -------
--  Adds the lease + retry columns the tiny-claimer scheduler needs to
--  safely claim due `campaign_sequence_actions` rows without two
--  concurrent claimer ticks racing each other, and to recover from
--  workers that die mid-flight.
--
--  Lease pattern
--  -------------
--    1. Claimer SELECTs `WHERE status='pending' AND scheduled_at<=NOW()`
--       with `FOR UPDATE SKIP LOCKED LIMIT 25`.
--    2. Claimer atomically UPDATEs status='claimed',
--       lease_expires_at = NOW() + 5 minutes.
--    3. Worker processes the action.
--    4. On success: status='ready_for_review' (review task created)
--       or 'executed' (auto-send path; v1.1).
--    5. On failure: status='failed', last_error set, retry_at scheduled.
--    6. On worker death: lease_expires_at < NOW() — the next claimer
--       tick re-includes the row via the partial index.
--
--  The 'claimed' status is added to the existing CHECK so the row
--  spends a finite time in-flight. 'ready_for_review' was already in
--  the enum from migration 249.
--
--  Backwards compatibility
--  -----------------------
--  All new columns are nullable / defaulted. Existing pending rows
--  continue to work unchanged.
--
--  Idempotency: re-runnable.
--
--  Verify (after apply):
--    \d campaign_sequence_actions   -- new columns visible
--    SELECT pg_get_constraintdef(oid)
--      FROM pg_constraint
--     WHERE conname = 'campaign_sequence_actions_status_check';
--    -- should include 'claimed' in the IN (...) list
--
--  Rollback:
--    ALTER TABLE public.campaign_sequence_actions
--      DROP COLUMN IF EXISTS lease_expires_at,
--      DROP COLUMN IF EXISTS attempts,
--      DROP COLUMN IF EXISTS last_error,
--      DROP COLUMN IF EXISTS retry_at;
--    -- (Status enum revert requires DROP + ADD CHECK; manual.)
-- ============================================================

ALTER TABLE public.campaign_sequence_actions
  ADD COLUMN IF NOT EXISTS lease_expires_at TIMESTAMPTZ NULL,
  ADD COLUMN IF NOT EXISTS attempts         INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS last_error       TEXT NULL,
  ADD COLUMN IF NOT EXISTS retry_at         TIMESTAMPTZ NULL;

-- Replace the status CHECK to include 'claimed' as a transient state
-- between 'pending' and 'ready_for_review' / 'executed' / 'failed'.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conname = 'campaign_sequence_actions_status_check'
  ) THEN
    ALTER TABLE public.campaign_sequence_actions
      DROP CONSTRAINT campaign_sequence_actions_status_check;
  END IF;
  ALTER TABLE public.campaign_sequence_actions
    ADD CONSTRAINT campaign_sequence_actions_status_check
    CHECK (status IN (
      'pending',
      'claimed',           -- NEW (P1-1) — held by a claimer; lease_expires_at set
      'ready_for_review',  -- review task created; awaiting human approval
      'approved',
      'executed',
      'cancelled',
      'failed',
      'skipped'
    ));
END $$;

-- Replace the due-claim partial index. The new predicate also
-- re-includes stale 'claimed' rows whose lease has expired so the
-- next claimer tick self-heals dead workers without manual repair.
DROP INDEX IF EXISTS public.idx_campaign_sequence_actions_due;

CREATE INDEX IF NOT EXISTS idx_campaign_sequence_actions_due
  ON public.campaign_sequence_actions(scheduled_at, lease_expires_at)
  WHERE status = 'pending'
     OR (status = 'claimed' AND lease_expires_at IS NOT NULL);

COMMENT ON COLUMN public.campaign_sequence_actions.lease_expires_at IS
  'V3 P1-1. Set when the claimer atomically transitions a pending row to status=claimed. The next claimer tick re-includes this row if the lease has expired (worker died mid-flight). NULL when status is anything other than claimed.';

COMMENT ON COLUMN public.campaign_sequence_actions.attempts IS
  'V3 P1-1. Increments on every claim attempt regardless of outcome. Used by P1-5 stale-claim observability and (later) by exponential-backoff retry.';

COMMENT ON COLUMN public.campaign_sequence_actions.last_error IS
  'V3 P1-1. Most recent error message from a failed worker. Cleared on next successful claim.';

COMMENT ON COLUMN public.campaign_sequence_actions.retry_at IS
  'V3 P1-1. When set, the next claimer tick will treat this as the effective scheduled_at (deferred retry after a failure). NULL when no retry is scheduled.';

-- ============================================================
--  RPC: claim_due_sequence_actions
-- ============================================================
--
--  Atomic claim primitive used by the Vercel claimer endpoint. The
--  PostgREST/supabase-js client doesn't expose
--  `SELECT ... FOR UPDATE SKIP LOCKED` directly, so we wrap the
--  claim in a SECURITY DEFINER function that:
--    1. SELECTs eligible due rows with FOR UPDATE SKIP LOCKED
--    2. UPDATEs them in place to status='claimed' + lease set
--    3. RETURNS the claimed rows
--
--  Eligibility predicate (matches the partial index above):
--    status='pending'          AND scheduled_at <= NOW()
--      with retry_at unset OR retry_at <= NOW()
--    OR
--    status='claimed'          AND lease_expires_at < NOW()
--      (stale claim — recover the row)
--
--  Idempotent: re-runnable.
--
--  Verify (after apply):
--    SELECT proname, prosrc FROM pg_proc WHERE proname='claim_due_sequence_actions';
-- ============================================================

CREATE OR REPLACE FUNCTION public.claim_due_sequence_actions(
  p_now              TIMESTAMPTZ,
  p_lease_expires_at TIMESTAMPTZ,
  p_batch_size       INTEGER
) RETURNS TABLE (
  id                  UUID,
  campaign_contact_id UUID,
  channel             TEXT,
  action_type         TEXT,
  metadata            JSONB,
  scheduled_at        TIMESTAMPTZ,
  attempts            INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  WITH due AS (
    SELECT csa.id
      FROM public.campaign_sequence_actions csa
     WHERE (
            (csa.status = 'pending'
             AND csa.scheduled_at <= p_now
             AND (csa.retry_at IS NULL OR csa.retry_at <= p_now))
         OR (csa.status = 'claimed'
             AND csa.lease_expires_at IS NOT NULL
             AND csa.lease_expires_at < p_now)
           )
     ORDER BY csa.scheduled_at NULLS FIRST
     LIMIT p_batch_size
     FOR UPDATE SKIP LOCKED
  )
  UPDATE public.campaign_sequence_actions csa
     SET status            = 'claimed',
         lease_expires_at  = p_lease_expires_at,
         attempts          = COALESCE(csa.attempts, 0) + 1,
         updated_at        = p_now
    FROM due
   WHERE csa.id = due.id
  RETURNING
    csa.id,
    csa.campaign_contact_id,
    csa.channel,
    csa.action_type,
    csa.metadata,
    csa.scheduled_at,
    csa.attempts;
END $$;

-- Lock down: only the BFF service role should call this. Default
-- privileges are revoked so the anon/authenticated roles cannot.
REVOKE ALL ON FUNCTION public.claim_due_sequence_actions(TIMESTAMPTZ, TIMESTAMPTZ, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.claim_due_sequence_actions(TIMESTAMPTZ, TIMESTAMPTZ, INTEGER) TO service_role;

COMMENT ON FUNCTION public.claim_due_sequence_actions IS
  'V3 P1-1 atomic claim primitive. Used by /api/internal/sequence/claim. SECURITY DEFINER so it runs with the function-owner privileges; only service_role is granted EXECUTE so anon/authenticated callers cannot invoke it.';

NOTIFY pgrst, 'reload schema';
