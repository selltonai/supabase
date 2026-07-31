-- 338 — Events + public registrations (5B). Operators create an event, share a
-- public /event/{slug} page (no login), and leads register on it. Registrations
-- upsert/attach a CRM contact so the event feeds the same pipeline as outreach.
--
-- Model:
--   • events — org-owned. `slug` is GLOBALLY unique (case-insensitive) because
--     the public URL is /event/{slug} with no org in the path. `status` gates
--     public visibility (only 'published' renders + accepts registrations).
--   • event_registrations — one row per (event, email). `contact_id` links the
--     registrant to a CRM contact (matched by email or created by the register
--     endpoint). organization_id is denormalized for RLS + fast org queries.
--
-- The public register endpoint writes via service_role (bypasses RLS); operator
-- reads/writes go through the org-scoped policies below.
--
-- Affected projects:
--   - selltonai: /event/{slug} page + /api/events (operator CRUD) +
--     /api/events/{slug}/register (public) read/write these.
-- Deploy: this migration before the selltonai event routes.
--
-- Additive + non-breaking. Safe to drop while empty.

CREATE TABLE IF NOT EXISTS public.events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  slug text NOT NULL,
  title text NOT NULL,
  description text,
  starts_at timestamptz,
  ends_at timestamptz,
  timezone text,
  location text,
  is_virtual boolean NOT NULL DEFAULT false,
  cover_image_url text,
  capacity integer CHECK (capacity IS NULL OR capacity >= 0),
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'published', 'closed')),
  -- Optional CRM list to drop registrants into (nullable; register endpoint adds
  -- the matched/created contact when set).
  crm_list_id uuid REFERENCES public.crm_lists(id) ON DELETE SET NULL,
  created_by text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- Global, case-insensitive slug uniqueness — the public URL has no org prefix.
CREATE UNIQUE INDEX IF NOT EXISTS uq_events_slug_lower
  ON public.events (lower(slug));
CREATE INDEX IF NOT EXISTS idx_events_org_id ON public.events(organization_id);

CREATE TABLE IF NOT EXISTS public.event_registrations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id uuid NOT NULL REFERENCES public.events(id) ON DELETE CASCADE,
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  contact_id uuid REFERENCES public.contacts(id) ON DELETE SET NULL,
  name text NOT NULL,
  email text NOT NULL,
  company text,
  phone text,
  status text NOT NULL DEFAULT 'registered' CHECK (status IN ('registered', 'cancelled', 'attended')),
  metadata jsonb,
  registered_at timestamptz NOT NULL DEFAULT now()
);

-- One registration per email per event (case-insensitive). The register endpoint
-- upserts on this so a double-submit updates rather than duplicates.
CREATE UNIQUE INDEX IF NOT EXISTS uq_event_registrations_event_email
  ON public.event_registrations (event_id, lower(email));
CREATE INDEX IF NOT EXISTS idx_event_registrations_event_id
  ON public.event_registrations(event_id);
CREATE INDEX IF NOT EXISTS idx_event_registrations_org_id
  ON public.event_registrations(organization_id);
CREATE INDEX IF NOT EXISTS idx_event_registrations_contact_id
  ON public.event_registrations(contact_id) WHERE contact_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.update_events_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS events_updated_at ON public.events;
CREATE TRIGGER events_updated_at
  BEFORE UPDATE ON public.events
  FOR EACH ROW
  EXECUTE FUNCTION public.update_events_updated_at();

ALTER TABLE public.events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.event_registrations ENABLE ROW LEVEL SECURITY;

-- events — org-scoped operator policies. Public read is served by the register/
-- page API via service_role (which bypasses RLS), so no anon SELECT policy here.
DROP POLICY IF EXISTS "Users can view events for their organization" ON public.events;
CREATE POLICY "Users can view events for their organization" ON public.events
  FOR SELECT USING (organization_id = current_setting('app.current_org_id', true));

DROP POLICY IF EXISTS "Users can insert events for their organization" ON public.events;
CREATE POLICY "Users can insert events for their organization" ON public.events
  FOR INSERT WITH CHECK (organization_id = current_setting('app.current_org_id', true));

DROP POLICY IF EXISTS "Users can update events for their organization" ON public.events;
CREATE POLICY "Users can update events for their organization" ON public.events
  FOR UPDATE USING (organization_id = current_setting('app.current_org_id', true));

DROP POLICY IF EXISTS "Users can delete events for their organization" ON public.events;
CREATE POLICY "Users can delete events for their organization" ON public.events
  FOR DELETE USING (organization_id = current_setting('app.current_org_id', true));

-- event_registrations — operators view/manage their org's registrations. Inserts
-- from the public page go through service_role.
DROP POLICY IF EXISTS "Users can view registrations for their organization" ON public.event_registrations;
CREATE POLICY "Users can view registrations for their organization" ON public.event_registrations
  FOR SELECT USING (organization_id = current_setting('app.current_org_id', true));

DROP POLICY IF EXISTS "Users can update registrations for their organization" ON public.event_registrations;
CREATE POLICY "Users can update registrations for their organization" ON public.event_registrations
  FOR UPDATE USING (organization_id = current_setting('app.current_org_id', true));

DROP POLICY IF EXISTS "Users can delete registrations for their organization" ON public.event_registrations;
CREATE POLICY "Users can delete registrations for their organization" ON public.event_registrations
  FOR DELETE USING (organization_id = current_setting('app.current_org_id', true));

COMMENT ON TABLE public.events IS
  '5B — operator-created events with a public /event/{slug} registration page. slug is globally unique (case-insensitive); only status=published renders + accepts registrations.';
COMMENT ON TABLE public.event_registrations IS
  '5B — public event registrations. One row per (event, lower(email)); contact_id links to the matched/created CRM contact so registrants feed the pipeline.';

-- Verify:
--   select column_name, data_type from information_schema.columns
--   where table_name in ('events','event_registrations') order by table_name, ordinal_position;
