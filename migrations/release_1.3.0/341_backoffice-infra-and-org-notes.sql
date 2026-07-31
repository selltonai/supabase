-- ============================================================
-- Backoffice shared infrastructure and Org 360 notes/tags
-- Projects:
--   - backoffice: audit events, alert dedup state, org notes/tags
-- Notes:
--   - Additive and service-role only. Backoffice write paths must tolerate
--     missing tables during staggered env upgrades.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.backoffice_audit_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  actor TEXT NOT NULL,
  action TEXT NOT NULL,
  organization_id TEXT REFERENCES public.organization(id) ON DELETE SET NULL,
  resource_type TEXT,
  resource_id TEXT,
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_backoffice_audit_events_org_time
  ON public.backoffice_audit_events(organization_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_backoffice_audit_events_action_time
  ON public.backoffice_audit_events(action, created_at DESC);

CREATE TABLE IF NOT EXISTS public.backoffice_alert_state (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id TEXT NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  alert_type TEXT NOT NULL,
  last_state TEXT,
  last_state_hash TEXT,
  last_fired_at TIMESTAMPTZ,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (organization_id, alert_type)
);

CREATE INDEX IF NOT EXISTS idx_backoffice_alert_state_type_time
  ON public.backoffice_alert_state(alert_type, updated_at DESC);

CREATE TABLE IF NOT EXISTS public.backoffice_org_notes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id TEXT NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  body TEXT NOT NULL,
  visibility TEXT NOT NULL DEFAULT 'internal',
  is_pinned BOOLEAN NOT NULL DEFAULT FALSE,
  created_by TEXT,
  updated_by TEXT,
  archived_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (visibility IN ('internal','support','sales'))
);

CREATE INDEX IF NOT EXISTS idx_backoffice_org_notes_org_time
  ON public.backoffice_org_notes(organization_id, archived_at, created_at DESC);

CREATE TABLE IF NOT EXISTS public.backoffice_org_tags (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id TEXT NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  tag TEXT NOT NULL,
  color TEXT,
  created_by TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (organization_id, tag)
);

CREATE INDEX IF NOT EXISTS idx_backoffice_org_tags_tag
  ON public.backoffice_org_tags(tag);

CREATE OR REPLACE FUNCTION public.update_backoffice_infra_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS backoffice_alert_state_updated_at ON public.backoffice_alert_state;
CREATE TRIGGER backoffice_alert_state_updated_at
  BEFORE UPDATE ON public.backoffice_alert_state
  FOR EACH ROW
  EXECUTE FUNCTION public.update_backoffice_infra_updated_at();

DROP TRIGGER IF EXISTS backoffice_org_notes_updated_at ON public.backoffice_org_notes;
CREATE TRIGGER backoffice_org_notes_updated_at
  BEFORE UPDATE ON public.backoffice_org_notes
  FOR EACH ROW
  EXECUTE FUNCTION public.update_backoffice_infra_updated_at();

ALTER TABLE public.backoffice_audit_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.backoffice_alert_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.backoffice_org_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.backoffice_org_tags ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.backoffice_audit_events IS
  'Immutable audit log for backoffice admin mutations. Audit writes are best-effort and must not block the primary action.';
COMMENT ON TABLE public.backoffice_alert_state IS
  'Idempotency/dedup state for backoffice Slack alerts and daily digest scans.';
COMMENT ON TABLE public.backoffice_org_notes IS
  'Internal CRM-lite notes shown on Org 360 backoffice pages.';
COMMENT ON TABLE public.backoffice_org_tags IS
  'Internal CRM-lite tags shown on Org 360 backoffice pages.';
