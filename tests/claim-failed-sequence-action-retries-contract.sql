\set ON_ERROR_STOP on
-- KAN-306 W12 contract for next-release/383_claim-failed-sequence-action-retries.
-- Run against an isolated PostgreSQL test database that already has
-- public.campaign_contacts (260) and public.campaign_sequence_actions (261 + 263):
--   psql -X -v ON_ERROR_STOP=1 -f tests/claim-failed-sequence-action-retries-contract.sql
-- Fixtures and migration application roll back together.
BEGIN;

-- Applied twice: the migration must be idempotent.
\ir ../migrations/next-release/383_claim-failed-sequence-action-retries.sql
\ir ../migrations/next-release/383_claim-failed-sequence-action-retries.sql

INSERT INTO public.campaign_contacts (id, campaign_id, contact_id, organization_id, owner_user_id, journey_state)
VALUES (
  '30000000-0000-0000-0000-000000000001',
  '30000000-0000-0000-0000-0000000000c1',
  '30000000-0000-0000-0000-0000000000a1',
  'org_w12_claim_contract',
  'user_w12_claim_contract',
  'queued_invite'
);

-- p_now for every call below is 2026-09-27 12:00 UTC.
INSERT INTO public.campaign_sequence_actions
  (id, campaign_contact_id, channel, action_type, status, scheduled_at, retry_at, lease_expires_at, attempts)
VALUES
  -- claimable
  ('30000000-0000-0000-0000-000000000101', '30000000-0000-0000-0000-000000000001', 'linkedin', 'linkedin_invitation',
   'pending', '2026-09-27T11:00:00Z', NULL, NULL, 0),
  ('30000000-0000-0000-0000-000000000102', '30000000-0000-0000-0000-000000000001', 'linkedin', 'linkedin_invitation',
   'claimed', '2026-09-27T10:00:00Z', NULL, '2026-09-27T11:55:00Z', 1),
  ('30000000-0000-0000-0000-000000000103', '30000000-0000-0000-0000-000000000001', 'linkedin', 'linkedin_invitation',
   'failed', '2026-09-27T09:00:00Z', '2026-09-27T11:59:00Z', NULL, 1),
  -- not claimable
  ('30000000-0000-0000-0000-000000000104', '30000000-0000-0000-0000-000000000001', 'linkedin', 'linkedin_invitation',
   'failed', '2026-09-27T09:00:00Z', '2026-09-27T12:05:00Z', NULL, 1),   -- retry not due yet
  ('30000000-0000-0000-0000-000000000105', '30000000-0000-0000-0000-000000000001', 'linkedin', 'linkedin_invitation',
   'failed', '2026-09-27T09:00:00Z', NULL, NULL, 3),                      -- retries exhausted
  ('30000000-0000-0000-0000-000000000106', '30000000-0000-0000-0000-000000000001', 'linkedin', 'linkedin_invitation',
   'skipped', '2026-09-27T09:00:00Z', '2026-09-27T11:00:00Z', NULL, 1),
  ('30000000-0000-0000-0000-000000000107', '30000000-0000-0000-0000-000000000001', 'linkedin', 'linkedin_invitation',
   'claimed', '2026-09-27T09:00:00Z', NULL, '2026-09-27T12:03:00Z', 1),  -- lease still live
  ('30000000-0000-0000-0000-000000000108', '30000000-0000-0000-0000-000000000001', 'linkedin', 'linkedin_invitation',
   'pending', '2026-09-27T09:00:00Z', '2026-09-27T12:10:00Z', NULL, 0),  -- pending, retry_at in the future
  ('30000000-0000-0000-0000-000000000109', '30000000-0000-0000-0000-000000000001', 'linkedin', 'linkedin_invitation',
   'failed', '2026-07-01T09:00:00Z', '2026-07-01T09:05:00Z', NULL, 1),   -- pre-383 retry, months old
  ('30000000-0000-0000-0000-000000000110', '30000000-0000-0000-0000-000000000001', 'linkedin', 'linkedin_invitation',
   'failed', '2026-09-20T11:00:00Z', '2026-09-20T12:00:00Z', NULL, 1);   -- exactly 7 days old: excluded (bound is >)

DO $$
DECLARE
  claimed_ids UUID[];
BEGIN
  SELECT array_agg(c.id ORDER BY c.id) INTO claimed_ids
    FROM public.claim_due_sequence_actions(
      '2026-09-27T12:00:00Z'::timestamptz,
      '2026-09-27T12:05:00Z'::timestamptz,
      25
    ) c;

  IF claimed_ids IS DISTINCT FROM ARRAY[
    '30000000-0000-0000-0000-000000000101',
    '30000000-0000-0000-0000-000000000102',
    '30000000-0000-0000-0000-000000000103'
  ]::uuid[] THEN
    RAISE EXCEPTION 'claim must return pending-due, lease-expired and failed-retry-due (last 7 days) rows only, got %', claimed_ids;
  END IF;

  -- The failed row is claimed exactly like the others (lease, attempts + 1).
  IF NOT EXISTS (
    SELECT 1 FROM public.campaign_sequence_actions
     WHERE id = '30000000-0000-0000-0000-000000000103'
       AND status = 'claimed'
       AND lease_expires_at = '2026-09-27T12:05:00Z'::timestamptz
       AND attempts = 2
  ) THEN
    RAISE EXCEPTION 'failed retry row must be claimed with the lease and attempts + 1';
  END IF;

  -- Untouched rows keep their status.
  IF EXISTS (
    SELECT 1 FROM public.campaign_sequence_actions
     WHERE id IN (
       '30000000-0000-0000-0000-000000000104',
       '30000000-0000-0000-0000-000000000105',
       '30000000-0000-0000-0000-000000000106',
       '30000000-0000-0000-0000-000000000107',
       '30000000-0000-0000-0000-000000000108',
       '30000000-0000-0000-0000-000000000109',
       '30000000-0000-0000-0000-000000000110'
     )
       AND status = 'claimed'
       AND lease_expires_at = '2026-09-27T12:05:00Z'::timestamptz
  ) THEN
    RAISE EXCEPTION 'exhausted, not-yet-due, older-than-7-days, skipped, live-lease and future-retry rows must not be claimed';
  END IF;

  -- A second call in the same instant claims nothing more.
  IF EXISTS (
    SELECT 1 FROM public.claim_due_sequence_actions(
      '2026-09-27T12:00:00Z'::timestamptz,
      '2026-09-27T12:05:00Z'::timestamptz,
      25
    )
  ) THEN
    RAISE EXCEPTION 'a claimed row must not be claimed twice while its lease is live';
  END IF;

  -- Security and grants as in 267.
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc
     WHERE oid = 'public.claim_due_sequence_actions(timestamptz, timestamptz, integer)'::regprocedure
       AND prosecdef
  ) THEN
    RAISE EXCEPTION 'claim_due_sequence_actions must stay SECURITY DEFINER';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role')
     AND NOT has_function_privilege('service_role',
       'public.claim_due_sequence_actions(timestamptz, timestamptz, integer)', 'EXECUTE') THEN
    RAISE EXCEPTION 'service_role must keep EXECUTE';
  END IF;

  IF to_regclass('public.idx_campaign_sequence_actions_failed_retry') IS NULL THEN
    RAISE EXCEPTION 'idx_campaign_sequence_actions_failed_retry must exist';
  END IF;
END $$;

ROLLBACK;
