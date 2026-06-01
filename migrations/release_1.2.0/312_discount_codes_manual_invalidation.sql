-- ============================================================
-- Onboarding activation: reusable discount codes with manual invalidation
-- Projects:
--   - selltonai: validates activation discount codes
-- App changes required together:
--   - validateActivationCode should reject rows where is_active = false.
--
-- Usage:
--   Unlimited reusable code: max_uses = NULL, expires_at = NULL, is_active = true
--   Manual invalidation:    UPDATE public.discount_codes SET is_active = false WHERE code = 'CODE';
-- ============================================================

ALTER TABLE public.discount_codes
  ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS invalidated_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS invalidated_by TEXT;

CREATE INDEX IF NOT EXISTS idx_discount_codes_active
  ON public.discount_codes(applies_to, is_active);

COMMENT ON COLUMN public.discount_codes.is_active IS
  'Manual kill switch for discount codes. Set false to invalidate without deleting redemption history.';

COMMENT ON COLUMN public.discount_codes.invalidated_at IS
  'Optional timestamp for manual discount-code invalidation.';

COMMENT ON COLUMN public.discount_codes.invalidated_by IS
  'Optional actor identifier for manual discount-code invalidation.';
