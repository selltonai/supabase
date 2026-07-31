\set ON_ERROR_STOP on

-- Run against a database containing migrations/full_schema.sql:
--   psql -X -v ON_ERROR_STOP=1 -f tests/dashboard-email-reply-events-contract.sql
BEGIN;

\ir ../migrations/release-next/354_dashboard-email-reply-events.sql

INSERT INTO public.organization (id, name)
VALUES ('org_dashboard_reply_contract', 'Dashboard Reply Contract');

INSERT INTO public.contacts (id, organization_id, name)
VALUES ('10000000-0000-0000-0000-000000000001', 'org_dashboard_reply_contract', 'Reply Contract Contact');

INSERT INTO public.campaigns (id, organization_id, user_id, name)
VALUES ('20000000-0000-0000-0000-000000000001', 'org_dashboard_reply_contract', 'user_contract', 'Reply Contract Campaign');

-- One legacy outreach send/reply. Canonical events on the same thread must not
-- double-count the conversion.
INSERT INTO public.campaign_emails (
  id,
  organization_id,
  campaign_id,
  contact_id,
  status,
  message_id,
  thread_id,
  sent_at,
  replied_at,
  reply_received_at,
  created_at,
  metadata
)
VALUES (
  '30000000-0000-0000-0000-000000000001',
  'org_dashboard_reply_contract',
  '20000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000001',
  'replied',
  'outbound-message-1',
  'shared-thread-1',
  '2026-07-30T09:00:00Z',
  '2026-07-30T12:00:00Z',
  '2026-07-30T12:00:00Z',
  '2026-07-30T09:00:00Z',
  '{"email_type":"initial"}'::jsonb
);

-- A Tasks-page initial email is outreach. A conversational reply sent from the
-- same page is not a new outreach send and must stay out of the denominator.
INSERT INTO public.tasks (
  id,
  organization_id,
  title,
  status,
  contact_id,
  campaign_id,
  task_type,
  send_status,
  email_id,
  thread_id,
  sent_at,
  created_at,
  metadata
)
VALUES
  (
    '40000000-0000-0000-0000-000000000001',
    'org_dashboard_reply_contract',
    'Initial outreach',
    'completed',
    '10000000-0000-0000-0000-000000000001',
    '20000000-0000-0000-0000-000000000001',
    'review_draft',
    'sent_success',
    'outbound-message-2',
    'shared-thread-2',
    '2026-07-30T10:00:00Z',
    '2026-07-30T10:00:00Z',
    '{"email_type":"initial"}'::jsonb
  ),
  (
    '40000000-0000-0000-0000-000000000002',
    'org_dashboard_reply_contract',
    'Reply to prospect',
    'completed',
    '10000000-0000-0000-0000-000000000001',
    '20000000-0000-0000-0000-000000000001',
    'review_draft',
    'sent_success',
    'outbound-reply-message',
    'shared-thread-1',
    '2026-07-30T11:00:00Z',
    '2026-07-30T11:00:00Z',
    '{"emailType":"reply"}'::jsonb
  );

INSERT INTO public.email_reply_events (
  organization_id,
  dedup_key,
  email_id,
  account_id,
  thread_id,
  contact_id,
  campaign_id,
  received_at,
  classification,
  relevance
)
VALUES
  (
    'org_dashboard_reply_contract',
    'gmail:inbound-message-1',
    'inbound-message-1',
    'account-1',
    'shared-thread-1',
    '10000000-0000-0000-0000-000000000001',
    '20000000-0000-0000-0000-000000000001',
    '2026-07-30T13:00:00Z',
    'REAL_PERSON',
    'PROSPECTING_RELATED'
  ),
  (
    'org_dashboard_reply_contract',
    'gmail:inbound-message-2',
    'inbound-message-2',
    'account-1',
    'shared-thread-1',
    '10000000-0000-0000-0000-000000000001',
    '20000000-0000-0000-0000-000000000001',
    '2026-07-30T14:00:00Z',
    'REAL_PERSON',
    'PROSPECTING_RELATED'
  ),
  (
    'org_other',
    'gmail:inbound-message-other-org',
    'inbound-message-other-org',
    'account-2',
    'shared-thread-1',
    '10000000-0000-0000-0000-000000000001',
    '20000000-0000-0000-0000-000000000001',
    '2026-07-30T15:00:00Z',
    'REAL_PERSON',
    'PROSPECTING_RELATED'
  );

-- Producer retries update one row instead of creating another event.
INSERT INTO public.email_reply_events (
  organization_id,
  dedup_key,
  email_id,
  account_id,
  thread_id,
  contact_id,
  campaign_id,
  received_at,
  classification,
  relevance
)
VALUES (
  'org_dashboard_reply_contract',
  'gmail:inbound-message-1',
  'inbound-message-1',
  'account-1',
  'shared-thread-1',
  '10000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000001',
  '2026-07-30T13:00:00Z',
  'REAL_PERSON',
  'PROSPECTING_RELATED'
)
ON CONFLICT (organization_id, dedup_key) DO UPDATE
SET updated_at = now();

DO $$
DECLARE
  v_event_count bigint;
  v_sent bigint;
  v_replied bigint;
BEGIN
  SELECT COUNT(*) INTO v_event_count
  FROM public.email_reply_events
  WHERE organization_id = 'org_dashboard_reply_contract'
    AND dedup_key = 'gmail:inbound-message-1';

  IF v_event_count <> 1 THEN
    RAISE EXCEPTION 'Idempotent producer key created % rows instead of 1', v_event_count;
  END IF;

  SELECT COALESCE(SUM(sent_count), 0), COALESCE(SUM(replied_count), 0)
  INTO v_sent, v_replied
  FROM public.dashboard_email_performance_rollup(
    'org_dashboard_reply_contract',
    '2026-07-30T00:00:00Z',
    '2026-07-31T00:00:00Z',
    ARRAY['20000000-0000-0000-0000-000000000001'::uuid]
  );

  IF v_sent <> 2 THEN
    RAISE EXCEPTION 'Expected 2 outreach sends (legacy + initial task), got %', v_sent;
  END IF;

  IF v_replied <> 1 THEN
    RAISE EXCEPTION 'Expected one first reply for the shared thread, got %', v_replied;
  END IF;

  IF has_table_privilege('authenticated', 'public.email_reply_events', 'SELECT') THEN
    RAISE EXCEPTION 'Authenticated gained direct access to backend analytics events';
  END IF;

  IF NOT has_table_privilege('service_role', 'public.email_reply_events', 'INSERT') THEN
    RAISE EXCEPTION 'Service role cannot write reply analytics events';
  END IF;

  IF has_function_privilege(
    'authenticated',
    'public.dashboard_email_performance_rollup(text,timestamptz,timestamptz,uuid[])',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'Authenticated gained direct dashboard rollup execution';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'email_reply_events'
      AND column_name = ANY(ARRAY['email', 'from', 'to', 'subject', 'body', 'message', 'snippet'])
  ) THEN
    RAISE EXCEPTION 'Reply analytics table contains a prohibited PII/content column';
  END IF;
END
$$;

SELECT 'dashboard-email-reply-events-contract: ok' AS result;

ROLLBACK;
