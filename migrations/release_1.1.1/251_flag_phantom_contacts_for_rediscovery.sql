-- Migration: Flag legacy phantom contacts for re-discovery
-- Release: 1.1.1
-- Affected services: selltonai-modal, selltonai, backoffice
-- Purpose:
--   Non-destructive cleanup for legacy placeholder contacts created from
--   company-only CSV/CRM rows. Creates backup snapshots first, then flags
--   phantoms so campaign enrollment can treat their companies as orphaned
--   and run AI-Ark recovery.
-- Rollback:
--   Use contacts_phantom_backup_20260520.contact_snapshot to restore prior
--   processing_status values for any contact id if needed.

CREATE TABLE IF NOT EXISTS public.contacts_phantom_backup_20260520 (
  id uuid PRIMARY KEY,
  organization_id text NOT NULL,
  processing_status text,
  contact_snapshot jsonb NOT NULL,
  backed_up_at timestamptz NOT NULL DEFAULT now(),
  backup_reason text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.company_contacts_phantom_backup_20260520 (
  id uuid PRIMARY KEY,
  contact_id uuid NOT NULL,
  company_id uuid NOT NULL,
  organization_id text,
  relationship_snapshot jsonb NOT NULL,
  backed_up_at timestamptz NOT NULL DEFAULT now(),
  backup_reason text NOT NULL
);

ALTER TABLE public.contacts_phantom_backup_20260520 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_contacts_phantom_backup_20260520 ENABLE ROW LEVEL SECURITY;

INSERT INTO public.contacts_phantom_backup_20260520 (
  id,
  organization_id,
  processing_status,
  contact_snapshot,
  backup_reason
)
SELECT
  c.id,
  c.organization_id,
  c.processing_status,
  to_jsonb(c),
  'pre-phantom-pending-rediscovery cleanup'
FROM public.contacts c
WHERE NULLIF(BTRIM(c.firstname), '') IS NULL
  AND NULLIF(BTRIM(c.lastname), '') IS NULL
  AND NULLIF(BTRIM(c.email), '') IS NULL
  AND NULLIF(BTRIM(c.linkedin_url), '') IS NULL
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.company_contacts_phantom_backup_20260520 (
  id,
  contact_id,
  company_id,
  organization_id,
  relationship_snapshot,
  backup_reason
)
SELECT
  cc.id,
  cc.contact_id,
  cc.company_id,
  cc.organization_id,
  to_jsonb(cc),
  'pre-phantom-pending-rediscovery cleanup'
FROM public.company_contacts cc
JOIN public.contacts c ON c.id = cc.contact_id
WHERE NULLIF(BTRIM(c.firstname), '') IS NULL
  AND NULLIF(BTRIM(c.lastname), '') IS NULL
  AND NULLIF(BTRIM(c.email), '') IS NULL
  AND NULLIF(BTRIM(c.linkedin_url), '') IS NULL
ON CONFLICT (id) DO NOTHING;

ALTER TABLE public.contacts
  DROP CONSTRAINT IF EXISTS contacts_processing_status_check;

ALTER TABLE public.contacts
  ADD CONSTRAINT contacts_processing_status_check
  CHECK (processing_status = ANY (ARRAY[
    'pending'::text,
    'processing'::text,
    'completed'::text,
    'processed'::text,
    'failed'::text,
    'imported'::text,
    'phantom'::text,
    'phantom_pending_rediscovery'::text
  ])) NOT VALID;

UPDATE public.contacts
SET
  processing_status = 'phantom_pending_rediscovery',
  updated_at = now()
WHERE NULLIF(BTRIM(firstname), '') IS NULL
  AND NULLIF(BTRIM(lastname), '') IS NULL
  AND NULLIF(BTRIM(email), '') IS NULL
  AND NULLIF(BTRIM(linkedin_url), '') IS NULL
  AND processing_status IS DISTINCT FROM 'phantom_pending_rediscovery';

CREATE INDEX IF NOT EXISTS idx_contacts_phantom_pending_rediscovery
  ON public.contacts (organization_id, updated_at DESC)
  WHERE processing_status = 'phantom_pending_rediscovery';

COMMENT ON TABLE public.contacts_phantom_backup_20260520 IS
  'Backup of contact rows before release 1.1.1 phantom cleanup flagging.';

COMMENT ON TABLE public.company_contacts_phantom_backup_20260520 IS
  'Backup of company-contact links for contacts flagged by release 1.1.1 phantom cleanup.';

COMMENT ON COLUMN public.contacts.processing_status IS
  'Status of contact data processing. Values: pending, processing, completed, processed, failed, imported, phantom, phantom_pending_rediscovery.';
