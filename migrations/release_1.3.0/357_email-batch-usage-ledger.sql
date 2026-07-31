-- 352 — V-4 batch usage idempotency.
--
-- Provider batches return token usage per custom_id. Keep a durable ledger next
-- to the task-creation ledger so drain retries can never double-charge usage and
-- a crash between task creation and usage capture can recover safely.
--
-- Affected projects:
--   - selltonai-modal: reads/writes this ledger in EmailBatchService.
--   - selltonai/backoffice: no request or response shape changes; existing batch
--     and usage readers remain compatible.
-- Deploy together: apply on the target environment before deploying/enabling the
-- V-4 stage batch drain. Additive and safe to retain on rollback.

ALTER TABLE public.email_batch_jobs
  ADD COLUMN IF NOT EXISTS usage_tracked_custom_ids jsonb NOT NULL DEFAULT '[]'::jsonb;

COMMENT ON COLUMN public.email_batch_jobs.usage_tracked_custom_ids IS
  'Anthropic batch custom_ids already persisted to public.usage at batch pricing.';
