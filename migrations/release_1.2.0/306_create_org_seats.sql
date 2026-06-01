-- ============================================================
-- Billing foundation: org_seats
-- Projects:
--   - selltonai: Clerk webhook writes seat lifecycle
--   - selltonai-modal: weekly billing rollup reads active seat overlap
-- App changes required together:
--   - Clerk webhook handlers for organizationMembership.created/deleted and user.deleted.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.org_seats (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id TEXT NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  clerk_user_id TEXT NOT NULL,
  clerk_membership_id TEXT NOT NULL,
  user_email TEXT,
  user_name TEXT,
  seat_status TEXT NOT NULL DEFAULT 'active',
  monthly_price DECIMAL(10,2) NOT NULL DEFAULT 15.00,
  active_since TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  active_until TIMESTAMPTZ,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  UNIQUE (clerk_membership_id),
  CONSTRAINT org_seats_status_check CHECK (seat_status IN ('active','suspended','terminated')),
  CONSTRAINT org_seats_monthly_price_check CHECK (monthly_price >= 0)
);

CREATE INDEX IF NOT EXISTS idx_org_seats_org_status
  ON public.org_seats(organization_id, seat_status);

CREATE INDEX IF NOT EXISTS idx_org_seats_user
  ON public.org_seats(clerk_user_id);

CREATE INDEX IF NOT EXISTS idx_org_seats_active_window
  ON public.org_seats(organization_id, active_since, active_until);

DROP TRIGGER IF EXISTS update_org_seats_updated_at ON public.org_seats;
CREATE TRIGGER update_org_seats_updated_at
  BEFORE UPDATE ON public.org_seats
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

COMMENT ON TABLE public.org_seats IS 'Per-user seat lifecycle for weekly prorated seat billing.';
COMMENT ON COLUMN public.org_seats.monthly_price IS 'Default is $15/month, billed weekly by active overlap.';
