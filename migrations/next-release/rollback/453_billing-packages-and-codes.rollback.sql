-- Reverses 453. Roll back 454 first (its functions read these tables), and ship the app and backoffice commits that
-- stop reading them: the wall then has no packages to offer and the Codes screen nothing to list.
-- Lossy once rows exist: dropping the tables drops every package edit, every issued code (with who redeemed it and
-- its invoice reference) and every refused attempt; dropping the activation_fees columns drops which activations
-- came from a card package, a code or a comp, and each code's invoiced price. Copy them first if any are set.
-- The grants and recommendations those activations wrote (workspace_allowances, cs_recommendations) stay.
SET LOCAL lock_timeout = '10s';

DROP TABLE IF EXISTS public.package_code_attempts;
DROP TABLE IF EXISTS public.package_codes;
DROP TABLE IF EXISTS public.billing_packages;

DROP INDEX IF EXISTS public.idx_activation_fees_payment_intent;

ALTER TABLE public.activation_fees
  DROP COLUMN IF EXISTS invoiced_price_cents,
  DROP COLUMN IF EXISTS invoice_ref,
  DROP COLUMN IF EXISTS source,
  DROP COLUMN IF EXISTS package_id;
