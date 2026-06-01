-- Stage-only onboarding activation discount code.
--
-- Run this manually in the stage Supabase SQL editor after the release-next
-- onboarding billing migrations have been applied:
--   304_create_discount_codes.sql
--   307_create_activation_fees.sql
--   312_discount_codes_manual_invalidation.sql
--
-- Code to enter in the onboarding UI:
--   STAGEFREE100
--
-- This code is intentionally reusable until manually invalidated:
--   UPDATE public.discount_codes
--      SET is_active = false,
--          invalidated_at = now(),
--          invalidated_by = 'your-name'
--    WHERE code = 'STAGEFREE100';

ALTER TABLE public.discount_codes
  ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS invalidated_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS invalidated_by TEXT;

INSERT INTO public.discount_codes (
    code,
    discount_type,
    discount_value,
    applies_to,
    max_uses,
    expires_at,
    is_active,
    notes,
    created_by
)
VALUES (
    'STAGEFREE100',
    'percentage',
    100,
    'activation',
    NULL,
    NULL,
    TRUE,
    'Reusable stage testing code for onboarding activation. Do not copy to production. Set is_active=false to invalidate.',
    'system'
)
ON CONFLICT (code) DO UPDATE SET
    discount_type = EXCLUDED.discount_type,
    discount_value = EXCLUDED.discount_value,
    applies_to = EXCLUDED.applies_to,
    max_uses = EXCLUDED.max_uses,
    expires_at = EXCLUDED.expires_at,
    is_active = TRUE,
    invalidated_at = NULL,
    invalidated_by = NULL,
    notes = EXCLUDED.notes;

SELECT
    code,
    discount_type,
    discount_value,
    applies_to,
    is_active,
    max_uses,
    uses_count,
    expires_at
FROM public.discount_codes
WHERE code = 'STAGEFREE100';
