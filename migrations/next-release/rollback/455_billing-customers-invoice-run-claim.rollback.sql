-- Reverses 455. Ship the engine commit that stops reading the column first; without it the engine already falls back
-- to running without the claim. Lossless: the column only holds a transient claim time.
SET LOCAL lock_timeout = '10s';

ALTER TABLE public.billing_customers DROP COLUMN IF EXISTS invoice_run_claimed_at;
