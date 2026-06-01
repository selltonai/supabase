-- ============================================================
-- Billing foundation: activation_fees
-- Projects:
--   - selltonai: Stripe webhook/free activation writes activation records
--   - backoffice/admin: reads activation payment history
-- App changes required together:
--   - Stripe checkout.session.completed handler should insert activation fee rows.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.activation_fees (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id TEXT NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  amount_paid_cents INTEGER NOT NULL DEFAULT 0,
  amount_discounted_cents INTEGER NOT NULL DEFAULT 0,
  currency TEXT NOT NULL DEFAULT 'usd',
  paid_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  stripe_checkout_session_id TEXT UNIQUE,
  stripe_payment_intent_id TEXT,
  discount_code TEXT REFERENCES public.discount_codes(code) ON DELETE SET NULL,
  activated_by TEXT,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT activation_fees_amount_paid_check CHECK (amount_paid_cents >= 0),
  CONSTRAINT activation_fees_amount_discounted_check CHECK (amount_discounted_cents >= 0)
);

CREATE INDEX IF NOT EXISTS idx_activation_fees_org
  ON public.activation_fees(organization_id, paid_at DESC);

CREATE INDEX IF NOT EXISTS idx_activation_fees_discount_code
  ON public.activation_fees(discount_code)
  WHERE discount_code IS NOT NULL;

COMMENT ON TABLE public.activation_fees IS 'One-time onboarding activation fee payment/comp audit records.';
