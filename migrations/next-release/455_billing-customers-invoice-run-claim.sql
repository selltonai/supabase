-- ============================================================
-- Migration: 455_billing-customers-invoice-run-claim (stage: next-release/455; renumber at promotion if 455 is taken)
-- Date:      2026-11-27
-- Ticket:    KAN-borce27 (PLAN_YEAR_END_PACKAGES_AND_ONBOARDING_2026_11_27, review fix 8 on the engine's grant draw)
-- Purpose:   billing_customers.invoice_run_claimed_at: one claim per workspace around the engine's invoice-creating
--            section, so the card-add catch-up and the Monday run never create invoices for the same workspace at
--            the same time (Stripe's pending invoice items would otherwise be swept by the wrong run). The engine
--            sets it with a compare-and-set, clears it when done, and treats a claim older than 30 minutes as stale.
-- Projects:  selltonai-modal writes and reads it (billing_service claim_invoice_run / release_invoice_run). Nothing
--            else reads it. Without the column the engine runs as before and skips the card-add catch-up.
-- Contract:  Additive. One nullable column, NULL on every existing row; no default, no index, no trigger.
-- ============================================================
SET LOCAL lock_timeout = '10s';

ALTER TABLE public.billing_customers
  ADD COLUMN IF NOT EXISTS invoice_run_claimed_at timestamptz;

COMMENT ON COLUMN public.billing_customers.invoice_run_claimed_at IS
  'When an engine invoice run claimed this workspace (compare-and-set); NULL when no run holds it. A claim older than 30 minutes is stale.';
