-- ============================================================
-- Onboarding activation: discount codes
-- Projects:
--   - selltonai: validates activation codes, free activation, admin code creation
--   - selltonai-modal: may read redemptions for billing/analytics later
-- App changes required together:
--   - DiscountCodeValidator, apply-code/free-activate routes, Stripe activation metadata handling.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.discount_codes (
  code TEXT PRIMARY KEY,
  discount_type TEXT NOT NULL,
  discount_value NUMERIC NOT NULL,
  applies_to TEXT NOT NULL DEFAULT 'activation',
  max_uses INTEGER,
  uses_count INTEGER NOT NULL DEFAULT 0,
  expires_at TIMESTAMPTZ,
  notes TEXT,
  created_by TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  CONSTRAINT discount_codes_discount_type_check CHECK (discount_type IN ('percentage','fixed_amount')),
  CONSTRAINT discount_codes_applies_to_check CHECK (applies_to IN ('activation','seats','tokens')),
  CONSTRAINT discount_codes_discount_value_check CHECK (discount_value >= 0),
  CONSTRAINT discount_codes_max_uses_check CHECK (max_uses IS NULL OR max_uses > 0),
  CONSTRAINT discount_codes_uses_count_check CHECK (uses_count >= 0)
);

CREATE TABLE IF NOT EXISTS public.discount_code_redemptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT NOT NULL REFERENCES public.discount_codes(code) ON DELETE RESTRICT,
  organization_id TEXT NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  redeemed_by TEXT NOT NULL,
  amount_discounted NUMERIC NOT NULL DEFAULT 0,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  redeemed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_discount_codes_expires_at
  ON public.discount_codes(expires_at)
  WHERE expires_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_discount_codes_applies_to
  ON public.discount_codes(applies_to);

CREATE INDEX IF NOT EXISTS idx_discount_code_redemptions_org
  ON public.discount_code_redemptions(organization_id, redeemed_at DESC);

CREATE INDEX IF NOT EXISTS idx_discount_code_redemptions_code
  ON public.discount_code_redemptions(code, redeemed_at DESC);

CREATE OR REPLACE FUNCTION public.increment_discount_code_uses(p_code TEXT)
RETURNS VOID AS $$
BEGIN
  UPDATE public.discount_codes
  SET uses_count = uses_count + 1
  WHERE code = upper(p_code);
END;
$$ LANGUAGE plpgsql;

COMMENT ON TABLE public.discount_codes IS 'Admin-created or system-created discount codes for activation, seats, or token usage.';
COMMENT ON TABLE public.discount_code_redemptions IS 'Redemption audit log for activation/paywall discount codes.';
