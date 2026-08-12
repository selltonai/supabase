-- ============================================================
-- Migration: 364_sequence-action-deferral-telemetry
-- Date:      2026-08-12
-- Purpose:   Make sequence-action DEFERRALS observable.
-- Projects:  selltonai-database/supabase (owner), selltonai (claim loop writes,
--            sequence health reads).
-- Contract:  Two additive nullable columns + one partial index. No backfill.
-- Depends:   none.
--
-- Why
-- ---
-- When the claim loop cannot process an action it DEFERS it: pushes
-- `scheduled_at` forward and writes the row back as `status='pending'`. That is
-- correct behaviour, and deliberately not an error — the code even clears
-- `last_error` on the way out ("defer is not an error").
--
-- The cost is that a deferral leaves NO trace whatsoever. The row looks
-- identical to one that has simply never been touched. Consequences seen in
-- production on 2026-08-12:
--   * an operator watched an action go pending → in-flight → back to pending
--     while every counter (sent / skipped / failed) stayed at 0, because a
--     deferral is none of those outcomes;
--   * 675 actions under cancelled campaigns had been deferring +24h EVERY TICK
--     for weeks, invisibly, inflating the pending queue to 1,475;
--   * the health widget reported "Healthy — no errors or stuck claims today"
--     for a queue in which nothing could move, because health was inferred
--     from the absence of errors.
--
-- Recording the reason turns "nothing is happening" into "247 actions deferred
-- today, top reason campaign_not_active" — the difference between an
-- afternoon of SQL and a glance.
--
-- Dedicated columns rather than a metadata JSONB key on purpose: the dashboard
-- query GROUPs BY reason, and the writer is on a per-minute path where a
-- read-modify-write to merge JSONB would be both slower and racy.
-- ============================================================

ALTER TABLE public.campaign_sequence_actions
  ADD COLUMN IF NOT EXISTS last_defer_reason TEXT,
  ADD COLUMN IF NOT EXISTS last_deferred_at  TIMESTAMPTZ;

COMMENT ON COLUMN public.campaign_sequence_actions.last_defer_reason IS
  'Why the claim loop last deferred this action instead of processing it (e.g. campaign_not_active:cancelled, outside_send_window:Europe/London, waiting_for_acceptance:unknown, campaign_paused). Distinct from last_error: a deferral is not a failure. Set on every defer; never cleared, so it also serves as "why was this last held up" after the action eventually runs.';

COMMENT ON COLUMN public.campaign_sequence_actions.last_deferred_at IS
  'When the action was last deferred. Powers the "deferred today" counter in the sequence health widget.';

-- Supports the dashboard query: count + group by reason over a recent window.
-- Partial, because only deferred rows are ever selected by it — keeps the index
-- small on a table where most rows have never been deferred.
CREATE INDEX IF NOT EXISTS idx_csa_deferred_recent
  ON public.campaign_sequence_actions (last_deferred_at DESC, last_defer_reason)
  WHERE last_deferred_at IS NOT NULL;

-- Verify after apply:
-- SELECT column_name, data_type FROM information_schema.columns
-- WHERE table_schema='public' AND table_name='campaign_sequence_actions'
--   AND column_name IN ('last_defer_reason','last_deferred_at');
--
-- Once the BFF is deployed, this becomes the answer to "why is nothing moving":
-- SELECT last_defer_reason, count(*), max(last_deferred_at) AS most_recent
-- FROM campaign_sequence_actions
-- WHERE last_deferred_at > now() - interval '24 hours'
-- GROUP BY 1 ORDER BY 2 DESC;
