-- ============================================================
-- Migration: claim-failed-sequence-action-retries (stage: next-release/383)
-- Date:      2026-09-27
-- Ticket:    KAN-306 W12 (fixes F12, work order 2026-09-25)
-- Purpose:   Let the LinkedIn sequence claimer pick up a FAILED action again
--            once its retry_at is due, as the BFF has always assumed.
-- Projects:  selltonai-database/supabase (owner); caller: selltonai
--            src/app/api/internal/sequence/claim/route.ts (claimDueActions ->
--            rpc claim_due_sequence_actions; recordOutcome writes the retry).
-- Contract:  Same function signature, return type, SECURITY DEFINER, owner,
--            REVOKE/GRANT as release_1.2.0/267. Only the WHERE gains a third
--            branch. One additive partial index. No column, constraint, RLS,
--            request, response, auth, webhook, cron or queue contract changes.
-- Depends:   public.campaign_sequence_actions (249 + 263 lease/retry columns),
--            public.claim_due_sequence_actions (263, last replaced by 267).
--
-- Why: recordOutcome (claim route) marks a failed action status='failed' with a
-- backoff retry_at (5 min, 15 min, then terminal after MAX_DISPATCH_RETRIES=3,
-- retry_at=NULL). The 267 claim function only selects status='pending' (due)
-- and status='claimed' with an expired lease, so a failed action was never
-- claimed again: the retry never ran, the journey stayed non-terminal forever,
-- the person was held from other campaigns (tier 3) and the campaign stayed
-- discovery_completed.
--
-- Design:
-- - New branch: status='failed' AND retry_at IS NOT NULL AND retry_at <= p_now
--   AND retry_at > p_now - 7 days. An exhausted action has retry_at=NULL and is
--   never selected. Other writers of status='failed' (the scheduled-dispatch
--   retry cap in the claim route) already set retry_at=NULL, so they stay
--   terminal. The BFF's backoff is at most 60 min, so the 7-day bound never cuts
--   off a live retry; it only keeps failed rows from before this migration (the
--   retry that never ran, possibly months old) asleep on apply. Those rows and
--   their journeys need a one-off decision, not a surprise send.
-- - Locking and lease semantics are unchanged: same FOR UPDATE SKIP LOCKED
--   sub-select, same UPDATE to status='claimed' with the lease, attempts+1,
--   same ORDER BY scheduled_at NULLS FIRST and LIMIT.
-- - Partial index on retry_at for the new branch. The 263 due index is
--   partial on pending/claimed; a disjunct it does not cover would otherwise
--   turn the every-minute claim into a sequential scan. With an index on each
--   branch the planner can BitmapOr them. Plain CREATE INDEX (the runner
--   rejects CONCURRENTLY): it takes a SHARE lock on campaign_sequence_actions
--   until the file commits; lock_timeout makes the file fail and roll back
--   instead of queueing writers. Re-run it (idempotent).
-- - Existing failed rows whose retry_at fell in the last 7 days become
--   claimable on apply (25 per tick, oldest scheduled_at first). Stage had none
--   on 2026-09-25; count them first on any other environment (verify query 3).
--
-- Idempotency: CREATE OR REPLACE FUNCTION; CREATE INDEX IF NOT EXISTS;
-- REVOKE/GRANT/COMMENT are re-runnable.
--
-- Rollback (restores the 267 definition verbatim — no failed branch at all —
-- then drops the index):
--   CREATE OR REPLACE FUNCTION public.claim_due_sequence_actions(
--     p_now              TIMESTAMPTZ,
--     p_lease_expires_at TIMESTAMPTZ,
--     p_batch_size       INTEGER
--   ) RETURNS TABLE (
--     id                  UUID,
--     campaign_contact_id UUID,
--     channel             TEXT,
--     action_type         TEXT,
--     metadata            JSONB,
--     scheduled_at        TIMESTAMPTZ,
--     attempts            INTEGER
--   )
--   LANGUAGE plpgsql
--   SECURITY DEFINER
--   AS $$
--   BEGIN
--     RETURN QUERY
--     WITH due AS (
--       SELECT csa.id
--         FROM public.campaign_sequence_actions csa
--        WHERE (
--               (csa.status = 'pending'
--                AND (csa.scheduled_at IS NULL OR csa.scheduled_at <= p_now)
--                AND (csa.retry_at IS NULL OR csa.retry_at <= p_now))
--            OR
--               (csa.status = 'claimed'
--                AND csa.lease_expires_at IS NOT NULL
--                AND csa.lease_expires_at < p_now)
--              )
--        ORDER BY csa.scheduled_at NULLS FIRST
--        LIMIT p_batch_size
--        FOR UPDATE SKIP LOCKED
--     )
--     UPDATE public.campaign_sequence_actions csa
--        SET status            = 'claimed',
--            lease_expires_at  = p_lease_expires_at,
--            attempts          = COALESCE(csa.attempts, 0) + 1,
--            updated_at        = p_now
--       FROM due
--      WHERE csa.id = due.id
--     RETURNING
--       csa.id, csa.campaign_contact_id, csa.channel, csa.action_type,
--       csa.metadata, csa.scheduled_at, csa.attempts;
--   END $$;
--   DROP INDEX IF EXISTS public.idx_campaign_sequence_actions_failed_retry;
-- Roll back the BFF (KAN-306 W12 branch) first or together: without this
-- branch its retries are silently dropped again (the pre-W12 behaviour).
-- ============================================================

SET LOCAL lock_timeout = '10s';

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
            -- True due rows. Honors retry_at when set.
            -- NULL scheduled_at means ASAP (per schema doc).
            (csa.status = 'pending'
             AND (csa.scheduled_at IS NULL OR csa.scheduled_at <= p_now)
             AND (csa.retry_at IS NULL OR csa.retry_at <= p_now))
         OR
            -- Stale claims: lease expired, recover the row.
            (csa.status = 'claimed'
             AND csa.lease_expires_at IS NOT NULL
             AND csa.lease_expires_at < p_now)
         OR
            -- KAN-306 W12: a failed action whose backoff retry is due.
            -- Exhausted actions have retry_at NULL and are never selected;
            -- retries older than 7 days (pre-383 leftovers) stay asleep.
            (csa.status = 'failed'
             AND csa.retry_at IS NOT NULL
             AND csa.retry_at <= p_now
             AND csa.retry_at > p_now - interval '7 days')
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

REVOKE ALL ON FUNCTION public.claim_due_sequence_actions(TIMESTAMPTZ, TIMESTAMPTZ, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.claim_due_sequence_actions(TIMESTAMPTZ, TIMESTAMPTZ, INTEGER) TO service_role;

COMMENT ON FUNCTION public.claim_due_sequence_actions IS
  'V3 P1-1 atomic claim primitive (updated 2026-05-06 to treat NULL scheduled_at as ASAP; 2026-09-27 KAN-306 W12 to re-claim failed rows whose retry_at is due within the last 7 days). Used by /api/internal/sequence/claim. SECURITY DEFINER.';

CREATE INDEX IF NOT EXISTS idx_campaign_sequence_actions_failed_retry
  ON public.campaign_sequence_actions (retry_at)
  WHERE status = 'failed' AND retry_at IS NOT NULL;

-- Verify (after apply):
--   1. The new branch is in the live definition:
--        SELECT position('csa.status = ''failed''' IN prosrc) > 0 AS has_failed_branch,
--               prosecdef
--          FROM pg_proc WHERE proname = 'claim_due_sequence_actions';
--      -- expect has_failed_branch = t, prosecdef = t
--   2. Grants unchanged (service_role only):
--        SELECT grantee, privilege_type FROM information_schema.routine_privileges
--         WHERE routine_name = 'claim_due_sequence_actions';
--   3. What becomes claimable on apply, and what stays asleep (run BEFORE):
--        SELECT count(*) FILTER (WHERE retry_at > now() - interval '7 days') AS failed_retry_due,
--               count(*) FILTER (WHERE retry_at <= now() - interval '7 days') AS failed_older_than_7d_stay_asleep,
--               min(retry_at) AS oldest_retry_at
--          FROM public.campaign_sequence_actions
--         WHERE status = 'failed' AND retry_at IS NOT NULL AND retry_at <= now();
--   4. The index exists:
--        SELECT to_regclass('public.idx_campaign_sequence_actions_failed_retry');
