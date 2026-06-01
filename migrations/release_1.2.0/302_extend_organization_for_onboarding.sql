-- ============================================================
-- Onboarding module foundation: organization onboarding fields
-- Projects:
--   - selltonai: routes onboarding, activation, admin, and dispatch state
--   - selltonai-modal: reads onboarding_status and writes pipeline milestones
-- App changes required together:
--   - New onboarding routes should update public.organization via funnel transition helper.
-- Notes:
--   - This repo uses public.organization, not public.organizations.
-- ============================================================

ALTER TABLE public.organization
  ADD COLUMN IF NOT EXISTS tier TEXT,
  ADD COLUMN IF NOT EXISTS onboarding_mode TEXT,
  ADD COLUMN IF NOT EXISTS activation_paid_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS onboarding_status TEXT,
  ADD COLUMN IF NOT EXISTS regions TEXT[],
  ADD COLUMN IF NOT EXISTS lines_of_business TEXT[],
  ADD COLUMN IF NOT EXISTS dispatch_suspended BOOLEAN,
  ADD COLUMN IF NOT EXISTS dispatch_suspended_reason TEXT,
  ADD COLUMN IF NOT EXISTS dispatch_suspended_at TIMESTAMPTZ;

UPDATE public.organization
SET
  tier = COALESCE(tier, 'starter'),
  onboarding_mode = COALESCE(onboarding_mode, 'autonomous'),
  onboarding_status = COALESCE(onboarding_status, 'pending'),
  dispatch_suspended = COALESCE(dispatch_suspended, FALSE);

ALTER TABLE public.organization
  ALTER COLUMN tier SET DEFAULT 'starter',
  ALTER COLUMN tier SET NOT NULL,
  ALTER COLUMN onboarding_mode SET DEFAULT 'autonomous',
  ALTER COLUMN onboarding_mode SET NOT NULL,
  ALTER COLUMN onboarding_status SET DEFAULT 'pending',
  ALTER COLUMN onboarding_status SET NOT NULL,
  ALTER COLUMN dispatch_suspended SET DEFAULT FALSE,
  ALTER COLUMN dispatch_suspended SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'organization_tier_check'
      AND conrelid = 'public.organization'::regclass
  ) THEN
    ALTER TABLE public.organization
      ADD CONSTRAINT organization_tier_check
      CHECK (tier IN ('starter','team','enterprise'));
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'organization_onboarding_mode_check'
      AND conrelid = 'public.organization'::regclass
  ) THEN
    ALTER TABLE public.organization
      DROP CONSTRAINT organization_onboarding_mode_check;
  END IF;

  ALTER TABLE public.organization
    ADD CONSTRAINT organization_onboarding_mode_check
    CHECK (onboarding_mode IN ('autonomous','sales_assisted','manual','multi_stakeholder'));

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'organization_onboarding_status_check'
      AND conrelid = 'public.organization'::regclass
  ) THEN
    ALTER TABLE public.organization
      ADD CONSTRAINT organization_onboarding_status_check
      CHECK (
        onboarding_status IN (
          'pending',
          'qualified',
          'researching',
          'v1_complete',
          'interviewing',
          'interviewing_complete',
          'v2_generating',
          'v2_complete',
          'kb_built',
          'approved',
          'launched',
          'failed'
        )
      );
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_organization_onboarding_status
  ON public.organization(onboarding_status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_organization_activation_paid_at
  ON public.organization(activation_paid_at)
  WHERE activation_paid_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_organization_dispatch_suspended
  ON public.organization(dispatch_suspended)
  WHERE dispatch_suspended = TRUE;

COMMENT ON COLUMN public.organization.tier IS 'One-time onboarding/sales motion tier: starter, team, or enterprise.';
COMMENT ON COLUMN public.organization.onboarding_mode IS 'Onboarding route mode: autonomous for self-serve, sales_assisted for enterprise routing. manual and multi_stakeholder are inert until Phase 2.';
COMMENT ON COLUMN public.organization.activation_paid_at IS 'Timestamp when the one-time onboarding activation fee was paid or comped.';
COMMENT ON COLUMN public.organization.onboarding_status IS 'Current funnel status for onboarding state machine and re-engagement.';
COMMENT ON COLUMN public.organization.dispatch_suspended IS 'When true, outbound dispatch paths must refuse to send.';
