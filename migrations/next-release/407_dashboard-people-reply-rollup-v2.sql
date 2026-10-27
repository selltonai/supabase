-- ============================================================
-- Migration: dashboard-people-reply-rollup-v2 (stage: next-release/407; the promotion keeps the number)
-- Date:      2026-10-19
-- Purpose:   KAN-322 FR-A11g: "People who replied" counts one person once across email and LinkedIn.
--            dashboard_people_reply_rollup_v2 = v1 (387), byte for byte in its email and LinkedIn rows, plus a third
--            row, channel 'all': the same three numbers over the union of both channels' people.
-- Projects:  selltonai-database/supabase (owner); reader: selltonai GET /api/dashboard/intelligence, behind
--            NEXT_PUBLIC_REFRESH_DASHBOARD_NUMBERS_ENABLED (src/features/dashboard/peopleNumbers.ts), which falls back
--            to v1 (and no 'all' figure) while v2 is missing.
-- Contract:  One new read-only function; v1 is kept (readers on v1 and the comparison log keep working). No table,
--            column, constraint, RLS, trigger, cron or queue change. Safe to drop.
-- Person:    email = contact_id; LinkedIn = coalesce(thread.contact_id, 'li:' || counterpart_provider_id), as v1. In the
--            'all' row only, an unlinked counterpart is matched to the workspace's contact with that LinkedIn id
--            (contacts.linkedin_provider_id, 365/362; the first by id if several), so a person emailed and messaged
--            on LinkedIn counts once; a counterpart with no contact stays a person of its own. The email and LinkedIn
--            rows keep v1's keys exactly.
-- Known limit: merged duplicate contacts (contacts.canonical_contact_id, 273) count as separate people, as in v1.
--   all.people_reached       distinct people sent outreach on either channel in the window
--   all.people_replied       distinct people with a countable reply on either channel in the window
--   all.reached_and_replied  of those reached, those whose last reply (either channel) is at or after their first
--                            outreach (either channel) in the window: never more than all.people_reached
-- Performance: as v1 (the same scans); the union adds one group over at most both channels' people, and one lookup
--            per unlinked counterpart by idx_contacts_org_linkedin_provider_id (365).
--            STABLE, SECURITY INVOKER, service_role only.
-- Rollback: next-release/rollback/406-407_dashboard-outcomes-and-people-v2.rollback.sql
-- ============================================================

CREATE OR REPLACE FUNCTION public.dashboard_people_reply_rollup_v2(
  p_org_id text,
  p_start timestamptz,
  p_end timestamptz,
  p_user_id text DEFAULT NULL
)
RETURNS TABLE (
  channel text,
  people_reached bigint,
  people_replied bigint,
  reached_and_replied bigint
)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path = public
AS $$
  WITH scoped_campaigns AS (
    SELECT c.id
    FROM public.campaigns c
    WHERE c.organization_id = p_org_id
      AND (p_user_id IS NULL OR c.user_id = p_user_id)
  ),
  email_sends AS (
    SELECT ce.contact_id, COALESCE(ce.sent_at, ce.created_at) AS sent_at
    FROM public.campaign_emails ce
    -- Scoped by campaign only: the campaigns are the organization's (an org filter here re-reads the org index per
    -- campaign, review 2026-10-02).
    WHERE ce.campaign_id IN (SELECT id FROM scoped_campaigns)
      AND ce.contact_id IS NOT NULL
      AND (ce.sent_at IS NOT NULL OR ce.status::text IN ('sent', 'delivered', 'opened', 'clicked', 'replied'))
      AND COALESCE(ce.sent_at, ce.created_at) >= p_start
      AND COALESCE(ce.sent_at, ce.created_at) < p_end
      AND LOWER(BTRIM(COALESCE(ce.metadata->>'email_type', ce.metadata->>'emailType', ce.metadata->>'type',
                               ce.metadata->>'reply_type', ce.metadata->>'replyType', ''))) <> ALL(ARRAY[
        'reply', 'meeting_response', 'inquiry_response', 'information_response', 'neutral_follow_up',
        'not_interested_response', 'general_response', 'timeslots', 'booking_confirmation'])
    UNION ALL
    SELECT t.contact_id, t.sent_at
    FROM public.tasks t
    WHERE t.organization_id = p_org_id
      AND t.task_type = 'review_draft'
      AND t.send_status = 'sent_success'
      AND t.sent_at IS NOT NULL
      AND t.sent_at >= p_start
      AND t.sent_at < p_end
      AND t.contact_id IS NOT NULL
      AND t.campaign_id IS NOT NULL
      AND t.campaign_id IN (SELECT id FROM scoped_campaigns)
      AND LOWER(BTRIM(COALESCE(t.metadata->>'email_type', t.metadata->>'emailType', t.metadata->>'type',
                               t.metadata->>'reply_type', t.metadata->>'replyType', ''))) <> ALL(ARRAY[
        'reply', 'meeting_response', 'inquiry_response', 'information_response', 'neutral_follow_up',
        'not_interested_response', 'general_response', 'timeslots', 'booking_confirmation'])
  ),
  email_reached AS (
    SELECT contact_id, MIN(sent_at) AS first_sent_at FROM email_sends GROUP BY contact_id
  ),
  email_replies AS (
    SELECT e.contact_id, MAX(e.received_at) AS last_reply_at
    FROM public.email_reply_events e
    WHERE e.organization_id = p_org_id
      AND e.contact_id IS NOT NULL
      AND e.campaign_id IN (SELECT id FROM scoped_campaigns)
      -- Every counted reply is inside the window (the rate's replies follow a first send that is inside it too).
      AND e.received_at >= p_start
      AND e.received_at < p_end
    GROUP BY e.contact_id
  ),
  li_threads AS (
    SELECT th.unipile_chat_id,
           COALESCE(th.contact_id::text, 'li:' || th.counterpart_provider_id) AS person
    FROM public.linkedin_threads th
    WHERE th.organization_id = p_org_id
      AND th.thread_origin IN ('sellton_outbound', 'campaign_inbound')
      AND (p_user_id IS NULL OR th.owner_user_id = p_user_id)
      AND (th.contact_id IS NOT NULL OR th.counterpart_provider_id IS NOT NULL)
  ),
  li_messages AS (
    SELECT t.person, m.direction, m.occurred_at
    FROM li_threads t
    JOIN public.linkedin_messages m
      ON m.unipile_chat_id = t.unipile_chat_id
     AND m.organization_id = p_org_id
    WHERE m.occurred_at >= p_start
      AND m.occurred_at < p_end
  ),
  li_people AS (
    SELECT person,
           MIN(occurred_at) FILTER (WHERE direction = 'outbound') AS first_sent_at,
           MAX(occurred_at) FILTER (WHERE direction = 'inbound') AS last_reply_at
    FROM li_messages
    GROUP BY person
  ),
  email_people AS (
    SELECT COALESCE(r.contact_id, e.contact_id) AS contact_id, r.first_sent_at, e.last_reply_at
    FROM email_reached r
    FULL JOIN email_replies e ON e.contact_id = r.contact_id
  ),
  -- FR-A11g: one person once across channels. A LinkedIn thread linked to a contact is that contact's (the email
  -- person's key); an unlinked counterpart stays its own person ('li:' + provider id). Per person: the first outreach
  -- on either channel and the last reply on either channel, so the rate's numerator is still a subset of reached.
  all_people AS (
    SELECT person, MIN(first_sent_at) AS first_sent_at, MAX(last_reply_at) AS last_reply_at
    FROM (
      SELECT contact_id::text AS person, first_sent_at, last_reply_at FROM email_people
      UNION ALL
      SELECT COALESCE(matched.id::text, lp.person), lp.first_sent_at, lp.last_reply_at
      FROM li_people lp
      LEFT JOIN LATERAL (
        SELECT c.id
        FROM public.contacts c
        WHERE lp.person LIKE 'li:%'
          AND c.organization_id = p_org_id
          AND c.linkedin_provider_id = substr(lp.person, 4)
        ORDER BY c.id
        LIMIT 1
      ) matched ON true
    ) both_channels
    GROUP BY person
  )
  SELECT 'email'::text,
    count(*) FILTER (WHERE first_sent_at IS NOT NULL),
    count(*) FILTER (WHERE last_reply_at IS NOT NULL),
    count(*) FILTER (WHERE first_sent_at IS NOT NULL AND last_reply_at >= first_sent_at)
  FROM email_people
  UNION ALL
  SELECT 'linkedin'::text,
    count(*) FILTER (WHERE first_sent_at IS NOT NULL),
    count(*) FILTER (WHERE last_reply_at IS NOT NULL),
    count(*) FILTER (WHERE first_sent_at IS NOT NULL AND last_reply_at >= first_sent_at)
  FROM li_people
  UNION ALL
  SELECT 'all'::text,
    count(*) FILTER (WHERE first_sent_at IS NOT NULL),
    count(*) FILTER (WHERE last_reply_at IS NOT NULL),
    count(*) FILTER (WHERE first_sent_at IS NOT NULL AND last_reply_at >= first_sent_at)
  FROM all_people
$$;

REVOKE ALL ON FUNCTION public.dashboard_people_reply_rollup_v2(text, timestamptz, timestamptz, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dashboard_people_reply_rollup_v2(text, timestamptz, timestamptz, text) TO service_role;

COMMENT ON FUNCTION public.dashboard_people_reply_rollup_v2(text, timestamptz, timestamptz, text) IS
  'KAN-322 FR-A11g: v1''s email and LinkedIn people reached / replied / reached-and-replied, plus channel ''all'': one person once across both channels.';

-- Verify (read-only, any database the migration ran on):
-- SELECT proname, has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_exec,
--        has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth_exec
--   FROM pg_proc p WHERE proname = 'dashboard_people_reply_rollup_v2';  -- expect one row, false, false
-- SELECT * FROM public.dashboard_people_reply_rollup_v2('<org>', now() - interval '30 days', now());
--   -- expect three rows; the email and linkedin rows equal v1's for the same arguments
