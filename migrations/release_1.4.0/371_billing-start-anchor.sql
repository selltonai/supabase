-- 371 — Billing start anchor.
--
-- Owner: Supabase. Consumers: selltonai-modal (enforces), selltonai (writes
-- card_added_at on activation checkout), Backoffice (reports).
--
-- What changes:
--   A workspace is invoiced only once it has BOTH a card on file and its first
--   campaign — whichever comes last is the moment billing starts. Work done
--   before that moment is never charged. Until now nothing recorded "when did
--   billing start", so selltonai-modal invoiced every workspace whose
--   onboarding reached kb_built: it created a Stripe customer, emailed an
--   invoice with a 1-day due date (weekly platform fee + seat fees, ~$12 even
--   at zero usage), then suspended the workspace and paused its campaigns.
--
--   - billing_customers.card_added_at    — when the first card was stored.
--   - billing_customers.billing_started_at — when recurring billing began.
--     NULL means the workspace is not billed at all.
--
-- Deployment order:
--   1. Apply this additive migration (safe on its own: nothing reads the
--      columns yet, and the backfill keeps current paying customers unchanged).
--   2. Deploy selltonai-modal, which enforces the rule and stamps
--      billing_started_at. Deployed before this migration it still works, it
--      just recomputes the value on each run.
--   3. Deploy selltonai (card_added_at on activation checkout, onboarding copy).
--   4. Deploy backoffice (reporting only).
--
-- Rollback: drop the two columns. selltonai-modal then falls back to
-- recomputing the start from the card date and the first campaign each run.

ALTER TABLE public.billing_customers
  ADD COLUMN IF NOT EXISTS card_added_at timestamptz;

ALTER TABLE public.billing_customers
  ADD COLUMN IF NOT EXISTS billing_started_at timestamptz;

COMMENT ON COLUMN public.billing_customers.card_added_at IS
  'When the first payment card was stored for this workspace. Half of the billing start rule.';

COMMENT ON COLUMN public.billing_customers.billing_started_at IS
  'When recurring weekly billing started: the later of card_added_at and the first campaign. NULL means the workspace is not invoiced. Usage before this moment is never charged.';

-- Backfill 1: workspaces that already have a card but no recorded date. The
-- row's own created_at is the closest known approximation.
UPDATE public.billing_customers
SET card_added_at = created_at
WHERE card_added_at IS NULL
  AND (card_last4 IS NOT NULL OR card_brand IS NOT NULL OR stripe_payment_method_id IS NOT NULL);

-- Backfill 2: workspaces that have already been invoiced keep billing exactly
-- as before — their start is the first period they were invoiced for.
UPDATE public.billing_customers bc
SET billing_started_at = first_invoice.period_start
FROM (
  SELECT organization_id, MIN(period_start) AS period_start
  FROM public.billing_invoices
  GROUP BY organization_id
) AS first_invoice
WHERE bc.billing_started_at IS NULL
  AND bc.organization_id = first_invoice.organization_id;

-- Everything else stays NULL on purpose: those workspaces stop being invoiced
-- until they have both a card and a first campaign. That is the fix.

CREATE INDEX IF NOT EXISTS idx_billing_customers_billing_started_at
  ON public.billing_customers (billing_started_at)
  WHERE billing_started_at IS NOT NULL;
