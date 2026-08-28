\set ON_ERROR_STOP on

-- Run against a database initialized from full_schema.sql:
--   psql -X -v ON_ERROR_STOP=1 -f tests/contact-automation-holds-contract.sql
-- Fixtures and migration application roll back together.
BEGIN;

\ir ../migrations/release_1.1.1/250_add_positive_followup_metadata_to_contacts.sql

INSERT INTO public.organization (id, name)
VALUES ('org_contact_automation_hold_validation', 'Contact Hold Validation');

INSERT INTO public.contacts (
  id,
  organization_id,
  name,
  stop_drafts,
  unsubscribed_at,
  do_not_contact,
  pipeline_stage,
  last_reply_sentiment,
  updated_at
)
VALUES
  (
    '20000000-0000-0000-0000-000000000101',
    'org_contact_automation_hold_validation',
    'Sequence Boundary Only',
    TRUE,
    NULL,
    FALSE,
    'LEAD',
    'POSITIVE',
    '2026-08-01T00:00:00Z'
  ),
  (
    '20000000-0000-0000-0000-000000000102',
    'org_contact_automation_hold_validation',
    'Unsubscribed Contact',
    TRUE,
    '2026-08-02T00:00:00Z',
    FALSE,
    'CLOSED_LOST',
    'NEGATIVE',
    '2026-08-02T00:00:00Z'
  ),
  (
    '20000000-0000-0000-0000-000000000103',
    'org_contact_automation_hold_validation',
    'Negative Reply Contact',
    TRUE,
    NULL,
    FALSE,
    'LEAD',
    'VERY_NEGATIVE',
    '2026-08-03T00:00:00Z'
  ),
  (
    '20000000-0000-0000-0000-000000000104',
    'org_contact_automation_hold_validation',
    'Marker Without Boundary',
    FALSE,
    '2026-08-04T00:00:00Z',
    FALSE,
    'CLOSED_LOST',
    'NEGATIVE',
    '2026-08-04T00:00:00Z'
  );

\ir ../migrations/release_1.3.0/366_contact-automation-holds.sql

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'contacts'
      AND column_name = 'automation_hold_at'
      AND data_type = 'timestamp with time zone'
  ) THEN
    RAISE EXCEPTION 'contacts.automation_hold_at is missing or has the wrong type';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'contacts'
      AND column_name = 'automation_hold_reason'
      AND data_type = 'text'
  ) THEN
    RAISE EXCEPTION 'contacts.automation_hold_reason is missing or has the wrong type';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.contacts
    WHERE id = '20000000-0000-0000-0000-000000000101'
      AND automation_hold_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'A stop_drafts-only sequence boundary was promoted to a hard hold';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.contacts
    WHERE id = '20000000-0000-0000-0000-000000000102'
      AND automation_hold_at = '2026-08-02T00:00:00Z'
      AND automation_hold_reason = 'unsubscribe'
  ) THEN
    RAISE EXCEPTION 'The historical unsubscribe hard stop was not backfilled';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.contacts
    WHERE id = '20000000-0000-0000-0000-000000000103'
      AND automation_hold_at IS NOT NULL
      AND automation_hold_reason = 'negative_reply'
  ) THEN
    RAISE EXCEPTION 'The historical negative-reply hard stop was not backfilled';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.contacts
    WHERE id = '20000000-0000-0000-0000-000000000104'
      AND automation_hold_at IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'A marker without the historical stop_drafts boundary was unexpectedly backfilled';
  END IF;
END
$$;

-- A managed migration must be safe when a deployment retries it.
\ir ../migrations/release_1.3.0/366_contact-automation-holds.sql

SELECT 'contact-automation-holds-contract: ok' AS result;

ROLLBACK;
