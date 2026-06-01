-- ============================================================
--  Migration: 254_fix_claim_rpc_null_scheduled_at
--  Date:      2026-05-06
--  Author:    Sellton AI — LinkedIn V3 / P1-1 self-review
-- ============================================================
--
--  Purpose
--  -------
--  The claim_due_sequence_actions RPC from migration 251 has a
--  correctness bug: rows with NULL scheduled_at are never eligible
--  for claim, but the schema comment on
--  campaign_sequence_actions.scheduled_at says NULL means
--  "as soon as the worker can pick it up."
--
--  Today's BFF code paths (P0-3 enrolment, advanceJourney) always
--  set scheduled_at explicitly, so this bug doesn't bite in normal
--  operation. But a manually-inserted row (or any future code path
--  that respects the documented NULL=ASAP semantics) would silently
--  never run.
--
--  Fix: change the predicate from `scheduled_at <= p_now` to
--  `(scheduled_at IS NULL OR scheduled_at <= p_now)`.
--
--  Idempotency: re-runnable. CREATE OR REPLACE FUNCTION.
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
  'V3 P1-1 atomic claim primitive (updated 2026-05-06 to treat NULL scheduled_at as ASAP). Used by /api/internal/sequence/claim. SECURITY DEFINER.';

NOTIFY pgrst, 'reload schema';
