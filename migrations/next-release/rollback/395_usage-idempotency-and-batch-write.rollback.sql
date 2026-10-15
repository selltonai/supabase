-- Reverses 395. The usage rows the function wrote stay (never DELETE from usage); only the key ledger goes, so a
-- resent phone batch would be written again. Stop the mobile service's sender before rolling back.
DROP FUNCTION IF EXISTS public.record_usage_batch_v1(jsonb);
DROP TABLE IF EXISTS public.usage_idempotency_keys;
