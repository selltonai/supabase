-- ============================================================
-- Migration: 365_add-contacts-linkedin-provider-id
-- Date:      2026-08-21
-- Purpose:   Add the canonical LinkedIn counterpart identifier to contacts.
-- Projects:  selltonai-database/supabase (owner), selltonai (reader/writer).
-- Contract:  Additive nullable column plus a partial lookup index. No existing
--            request, response, auth, webhook, cron, or queue contract changes.
-- Depends:   public.contacts. Must run before
--            362_backfill-contact-linkedin-provider-id.sql.
--
-- This migration was created after 362, so its numeric identifier is newer.
-- The Hetzner deployment manifest intentionally places it before the still-
-- pending 362 backfill. Migration identity is the full path plus SHA-256; no
-- previously deployed migration is renamed or modified.
-- ============================================================

ALTER TABLE public.contacts
  ADD COLUMN IF NOT EXISTS linkedin_provider_id TEXT;

COMMENT ON COLUMN public.contacts.linkedin_provider_id IS
  'LinkedIn member URN for this contact. Canonical organization-scoped counterpart-to-contact match key used by LinkedIn inbound and relation processing.';

CREATE INDEX IF NOT EXISTS idx_contacts_org_linkedin_provider_id
  ON public.contacts (organization_id, linkedin_provider_id)
  WHERE linkedin_provider_id IS NOT NULL;

-- Verification after apply:
-- SELECT column_name, data_type
-- FROM information_schema.columns
-- WHERE table_schema = 'public'
--   AND table_name = 'contacts'
--   AND column_name = 'linkedin_provider_id';
--
-- SELECT indexdef
-- FROM pg_indexes
-- WHERE schemaname = 'public'
--   AND indexname = 'idx_contacts_org_linkedin_provider_id';
