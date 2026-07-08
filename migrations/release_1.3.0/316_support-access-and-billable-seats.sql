-- Migration: Support access foundation and billable seat flags
-- Description: Adds non-member support session/audit tables and marks seats as billable/customer-owned.
-- Projects: backoffice creates support sessions; selltonai validates support access; selltonai-modal excludes non-billable/internal users from billing.
-- Application code: deploy together with support-session validation and billing exclusion logic.

ALTER TABLE public.org_seats
  ADD COLUMN IF NOT EXISTS is_billable boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS seat_type text NOT NULL DEFAULT 'customer';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'org_seats_seat_type_check'
      AND conrelid = 'public.org_seats'::regclass
  ) THEN
    ALTER TABLE public.org_seats
      ADD CONSTRAINT org_seats_seat_type_check CHECK (seat_type IN ('customer', 'internal_support', 'system'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_org_seats_billable
  ON public.org_seats(organization_id, is_billable, seat_type)
  WHERE active_until IS NULL;

COMMENT ON COLUMN public.org_seats.is_billable IS 'Whether this seat should be charged in customer billing';
COMMENT ON COLUMN public.org_seats.seat_type IS 'customer seats are billable; internal_support and system seats are excluded from billing';

CREATE TABLE IF NOT EXISTS public.internal_support_users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  clerk_user_id text UNIQUE,
  email text UNIQUE,
  display_name text,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT internal_support_users_identity_check CHECK (clerk_user_id IS NOT NULL OR email IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS idx_internal_support_users_active
  ON public.internal_support_users(active);

DROP TRIGGER IF EXISTS update_internal_support_users_updated_at ON public.internal_support_users;
CREATE TRIGGER update_internal_support_users_updated_at
  BEFORE UPDATE ON public.internal_support_users
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.support_workspace_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  support_user_id text NOT NULL,
  support_user_email text NOT NULL,
  reason text,
  ticket_url text,
  status text NOT NULL DEFAULT 'active',
  scopes text[] NOT NULL DEFAULT ARRAY['super_admin']::text[],
  one_time_token_hash text UNIQUE,
  session_token_hash text UNIQUE,
  exchanged_at timestamptz,
  expires_at timestamptz NOT NULL,
  revoked_at timestamptz,
  last_seen_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  CONSTRAINT support_workspace_sessions_status_check CHECK (status IN ('active', 'revoked', 'expired')),
  CONSTRAINT support_workspace_sessions_token_check CHECK (one_time_token_hash IS NOT NULL OR session_token_hash IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS idx_support_workspace_sessions_org_status
  ON public.support_workspace_sessions(organization_id, status, expires_at);

CREATE INDEX IF NOT EXISTS idx_support_workspace_sessions_support_user
  ON public.support_workspace_sessions(support_user_id, status, expires_at);

DROP TRIGGER IF EXISTS update_support_workspace_sessions_updated_at ON public.support_workspace_sessions;
CREATE TRIGGER update_support_workspace_sessions_updated_at
  BEFORE UPDATE ON public.support_workspace_sessions
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.support_audit_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id uuid REFERENCES public.support_workspace_sessions(id) ON DELETE SET NULL,
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  support_user_id text NOT NULL,
  support_user_email text NOT NULL,
  action text NOT NULL,
  resource_type text,
  resource_id text,
  request_method text,
  request_path text,
  ip_address inet,
  user_agent text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_support_audit_events_org_created
  ON public.support_audit_events(organization_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_support_audit_events_session_created
  ON public.support_audit_events(session_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public.support_resource_locks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  session_id uuid NOT NULL REFERENCES public.support_workspace_sessions(id) ON DELETE CASCADE,
  support_user_id text NOT NULL,
  resource_type text NOT NULL,
  resource_id text NOT NULL,
  lock_scope text NOT NULL DEFAULT 'write',
  expires_at timestamptz NOT NULL,
  released_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_support_resource_locks_active_resource
  ON public.support_resource_locks(organization_id, resource_type, resource_id, lock_scope)
  WHERE released_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_support_resource_locks_session
  ON public.support_resource_locks(session_id, expires_at);

ALTER TABLE public.internal_support_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_workspace_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_audit_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_resource_locks ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.internal_support_users IS 'Internal Sellton staff identities excluded from customer billing';
COMMENT ON TABLE public.support_workspace_sessions IS 'Short-lived non-member support access sessions for customer workspaces';
COMMENT ON TABLE public.support_audit_events IS 'Internal audit log for support workspace access and actions';
COMMENT ON TABLE public.support_resource_locks IS 'Optional short-lived support edit locks for risky workspace writes';
