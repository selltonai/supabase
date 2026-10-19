-- ============================================================
-- Migration: 404_user-calendar-connections (next-release; the same bytes on main and stage)
-- Date:      2026-10-19
-- Purpose:   KAN-309 (Borce 2026-09-28 "one global calendar, not per user"; Milka 2026-10-15: per-user Cal.com is the
--            target). One calendar connection per person per workspace. The workspace calendar in
--            organization_settings.api_credentials (cal_com_api_key / cal_com_event_type_id / cal_com_booking_url /
--            cal_com_timezone) stays the FALLBACK, used only while the sender has no row (or a row without that field).
--            A row with booking_url and no key is valid: that is the booking-link-only slice (old V3).
-- Projects:  Writer: selltonai /api/me/calendar only (service role; the caller's own row, organization from auth).
--            Reader: selltonai-modal services/calendar/sender_calendar.py only (service role).
--            "The sender" is the campaign owner for email and the LinkedIn seat owner for LinkedIn.
-- Secret:    api_key_ciphertext is AES-256-GCM, sealed by the BFF with CALENDAR_CREDENTIALS_KEY and bound to
--            "<organization_id>:<user_id>:cal_com" as associated data, so a ciphertext copied to another row does not
--            open. Format "v1:<iv b64>:<ciphertext+tag b64>"; the CHECK refuses anything else, so a plaintext key cannot
--            be stored by mistake. The plaintext key is never stored and never returned to a browser (the BFF returns
--            api_key_last4 only).
-- Access:    Only the service role. anon and authenticated get no table privileges (Supabase's default privileges
--            grant them; revoked below and checked at the end, which fails the migration if they leak).
--            RLS is ON with NO policies on purpose (deny by default), not the 338 org-scoped policy: this table holds a
--            secret and has no browser reader. The 338 policy keys on current_setting('app.current_org_id'), which
--            nothing in selltonai sets and which a session sets for itself, so it is not an authorization boundary.
--            As a second layer it would only open rows to every member of the organization if a grant ever came back;
--            with no policy, a stray grant still returns zero rows. The service role bypasses RLS. (402 does the same.)
-- Contract:  Additive. New table + trigger function. Safe to drop: Modal and the BFF treat a missing table as
--            "no connection" (the workspace calendar), so nothing else changes.
-- Rollback:  rollback/404_user-calendar-connections.rollback.sql
-- ============================================================

CREATE TABLE IF NOT EXISTS public.user_calendar_connections (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id     text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  user_id             text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  provider            text NOT NULL DEFAULT 'cal_com' CHECK (provider IN ('cal_com')),
  booking_url         text NULL CHECK (booking_url IS NULL OR (booking_url ~ '^https://[^[:space:]]+$' AND length(booking_url) <= 500)),
  event_type_id       text NULL CHECK (event_type_id IS NULL OR event_type_id ~ '^[0-9]{1,12}$'),
  timezone            text NULL CHECK (timezone IS NULL OR length(timezone) <= 64),
  api_key_ciphertext  text NULL CHECK (api_key_ciphertext IS NULL OR api_key_ciphertext LIKE 'v1:%'),
  api_key_last4       text NULL CHECK (api_key_last4 IS NULL OR length(api_key_last4) <= 4),
  status              text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'invalid')),
  last_verified_at    timestamptz NULL,
  last_error          text NULL,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT user_calendar_connections_one_per_provider UNIQUE (organization_id, user_id, provider)
);

-- The unique constraint's index leads with organization_id, so it serves organization lookups and the
-- organization cascade. The user cascade needs its own.
CREATE INDEX IF NOT EXISTS idx_user_calendar_connections_user
  ON public.user_calendar_connections (user_id);

CREATE OR REPLACE FUNCTION public.update_user_calendar_connections_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public.update_user_calendar_connections_updated_at() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS user_calendar_connections_updated_at ON public.user_calendar_connections;
CREATE TRIGGER user_calendar_connections_updated_at
  BEFORE UPDATE ON public.user_calendar_connections
  FOR EACH ROW
  EXECUTE FUNCTION public.update_user_calendar_connections_updated_at();

REVOKE ALL ON TABLE public.user_calendar_connections FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.user_calendar_connections TO service_role;

ALTER TABLE public.user_calendar_connections ENABLE ROW LEVEL SECURITY;
-- No policies on purpose (see the header).

COMMENT ON TABLE public.user_calendar_connections IS
  'KAN-309: a person''s own Cal.com connection in one workspace (booking link, event type, timezone, sealed API key). The workspace calendar in organization_settings.api_credentials is the fallback while a person has none. Service role only.';
COMMENT ON COLUMN public.user_calendar_connections.api_key_ciphertext IS
  'AES-256-GCM "v1:<iv b64>:<ciphertext+tag b64>", sealed by the selltonai BFF with CALENDAR_CREDENTIALS_KEY, associated data "<organization_id>:<user_id>:cal_com". Never plaintext.';
COMMENT ON COLUMN public.user_calendar_connections.status IS
  'active, or invalid (Cal.com refused the key). An invalid key does NOT fall back to the workspace calendar (decision B11); the booking link still does.';

DO $$
BEGIN
  IF has_table_privilege('anon', 'public.user_calendar_connections', 'SELECT')
     OR has_table_privilege('authenticated', 'public.user_calendar_connections', 'SELECT')
     OR has_table_privilege('anon', 'public.user_calendar_connections', 'INSERT')
     OR has_table_privilege('authenticated', 'public.user_calendar_connections', 'INSERT')
     OR has_table_privilege('anon', 'public.user_calendar_connections', 'UPDATE')
     OR has_table_privilege('authenticated', 'public.user_calendar_connections', 'UPDATE') THEN
    RAISE EXCEPTION '404: anon or authenticated has privileges on user_calendar_connections';
  END IF;
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.user_calendar_connections'::regclass) THEN
    RAISE EXCEPTION '404: RLS is off on user_calendar_connections';
  END IF;
END $$;

-- Verify (read-only):
-- SELECT has_table_privilege('anon', 'public.user_calendar_connections', 'SELECT') AS anon_read,             -- false
--        has_table_privilege('authenticated', 'public.user_calendar_connections', 'SELECT') AS user_read,    -- false
--        has_table_privilege('service_role', 'public.user_calendar_connections', 'SELECT') AS service_read,  -- true
--        (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.user_calendar_connections'::regclass) AS rls_on, -- true
--        (SELECT count(*) FROM pg_policies WHERE tablename = 'user_calendar_connections') AS policies;        -- 0
-- SELECT provider, status, count(*), count(api_key_ciphertext) AS with_key, count(booking_url) AS with_link
--   FROM public.user_calendar_connections GROUP BY 1, 2;
