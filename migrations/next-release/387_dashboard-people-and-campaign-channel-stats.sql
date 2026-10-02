-- ============================================================
-- Migration: dashboard-people-and-campaign-channel-stats (stage: next-release/387; renumber at promotion)
-- Date:      2026-10-02
-- Purpose:   KAN-322 FR-A11 (D9) and FR-A11b (D15): count outreach by PERSON, not by message, in one place.
--              1. dashboard_people_reply_rollup_v1  - the dashboard's email and LinkedIn people numbers.
--              2. campaign_channel_stats_v1         - per-campaign numbers for the Plays list.
-- Projects:  selltonai-database/supabase (owner); readers: selltonai
--            GET /api/dashboard/intelligence (FR-A11, behind NEXT_PUBLIC_REFRESH_DASHBOARD_NUMBERS_ENABLED)
--            GET /api/campaigns/channel-stats (FR-A11b, the Plays list).
-- Contract:  New read-only functions only. No table, column, constraint, RLS, trigger, cron or queue change.
--            Safe to drop (readers fall back to today's numbers when a function is missing).
-- Depends:   public.campaigns (user_id = owner), public.campaign_emails, public.tasks (review_draft sends),
--            public.email_reply_events (359), public.linkedin_threads (259 + 274 thread_origin),
--            public.linkedin_messages (257).
--
-- Definitions (work order Addendum A, D9 / D15):
--   Outreach email = the rows 359's dashboard_email_performance_rollup counts as sent: campaign_emails with a send
--     (sent_at, or a sent-like status) plus review_draft tasks with send_status = 'sent_success', excluding reply-type
--     emails (metadata email_type / type / reply_type in the reply list below). Only rows with a contact and a campaign
--     of the organization count.
--   Email person = contact_id. Email reply = a row in email_reply_events (its producer already drops OOO and
--     auto-replies). campaign_emails.replied_at is NOT used: it leaks OOO (api/campaigns/process-reply).
--   LinkedIn counted thread = thread_origin IN ('sellton_outbound', 'campaign_inbound'); personal threads never count.
--   LinkedIn person = coalesce(thread.contact_id, 'li:' || counterpart_provider_id).
--   LinkedIn reached = a person with an OUTBOUND message on a counted thread; replied = an INBOUND message there.
--   "Just me" (p_user_id): email = campaigns I own (campaigns.user_id), LinkedIn = threads on my seat
--     (linkedin_threads.owner_user_id), as the dashboard scopes today.
--
-- Performance: every person is grouped once (no per-person subquery); replied threads are found once and attached to
-- campaigns through the wanted campaign contacts (one CTE, hash-joined on contact). campaign_emails is read by
-- campaign. Indexes used: idx_tasks_dashboard_email_sent_rollup (the enum comparison below matches its partial
-- predicate), idx_campaign_emails_campaign_id, idx_email_reply_events_org_received / _org_campaign_received,
-- idx_linkedin_threads_org_recent, idx_linkedin_messages_chat, the linkedin_action_log campaign index (269),
-- campaign_contacts (campaign_id, ...) indexes. STABLE, SECURITY INVOKER, service_role only. Measured by the review on a
-- synthetic org (200k emails, 200k tasks, 50k threads, 300k messages).
--
-- Rollback: DROP FUNCTION IF EXISTS public.dashboard_people_reply_rollup_v1(text, timestamptz, timestamptz, text);
--           DROP FUNCTION IF EXISTS public.campaign_channel_stats_v1(text, uuid[]);
-- ============================================================

-- 1. Dashboard: people reached and replied, per channel, in one window.
--    people_reached          distinct people sent outreach in [p_start, p_end)
--    people_replied          distinct people with a countable reply in [p_start, p_end) (the "Replies" figure)
--    reached_and_replied     of people_reached, those who replied after their first outreach in the window and
--                            before p_end (the rate numerator, so the rate can never pass 100%)
CREATE OR REPLACE FUNCTION public.dashboard_people_reply_rollup_v1(
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
$$;

REVOKE ALL ON FUNCTION public.dashboard_people_reply_rollup_v1(text, timestamptz, timestamptz, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dashboard_people_reply_rollup_v1(text, timestamptz, timestamptz, text) TO service_role;

COMMENT ON FUNCTION public.dashboard_people_reply_rollup_v1(text, timestamptz, timestamptz, text) IS
  'KAN-322 D9: email and LinkedIn people reached / replied / reached-and-replied in a window, by person. Personal LinkedIn threads never count; email replies from email_reply_events (no OOO).';

-- 2. Plays list: one row per requested campaign of the organization, all time. Campaigns of other organizations
--    and unknown ids are not returned; a campaign with no activity returns zeros.
--    email_sent                outreach emails sent, de-duplicated like 359 (message id, then thread, then contact)
--    email_people_reached      distinct contacts sent outreach
--    email_people_replied      of those reached, contacts with a reply event on the campaign (never above reached)
--    linkedin_people_invited   distinct people with a successful invitation on the campaign (linkedin_action_log)
--    linkedin_people_accepted  campaign contacts whose relation is connected now (as the list shows today)
--    linkedin_people_messaged  distinct people with a successful message on the campaign
--    linkedin_people_replied   distinct people with an inbound message on a counted thread of the campaign: the thread
--                              carries the campaign, or (untagged) its contact is enrolled on the same LinkedIn account
--                              and replied after enrolling. Can exceed messaged: campaign_inbound people write first.
--    Known limit: a person seen once with a contact and once only by provider id counts as two.
CREATE OR REPLACE FUNCTION public.campaign_channel_stats_v1(
  p_org_id text,
  p_campaign_ids uuid[]
)
RETURNS TABLE (
  campaign_id uuid,
  email_sent bigint,
  email_people_reached bigint,
  email_people_replied bigint,
  linkedin_people_invited bigint,
  linkedin_people_accepted bigint,
  linkedin_people_messaged bigint,
  linkedin_people_replied bigint
)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path = public
AS $$
  WITH wanted AS (
    SELECT c.id FROM public.campaigns c
    WHERE c.organization_id = p_org_id AND c.id = ANY(p_campaign_ids)
  ),
  email_sends AS (
    -- The dedup keys are 359's, character for character.
    SELECT ce.campaign_id, ce.contact_id,
      CASE
        WHEN ce.message_id IS NOT NULL AND ce.message_id <> '' THEN 'message:' || ce.message_id
        WHEN ce.thread_id IS NOT NULL AND ce.thread_id <> '' AND ce.sent_at IS NOT NULL THEN
          'thread-sent:' || ce.campaign_id::text || ':' || ce.contact_id::text || ':' || ce.thread_id || ':' || ce.sent_at::text
        WHEN ce.sent_at IS NOT NULL THEN
          'campaign-contact-sent:' || ce.campaign_id::text || ':' || ce.contact_id::text || ':' || ce.sent_at::text
        ELSE 'campaign-email:' || ce.id::text
      END AS dedup_key
    FROM public.campaign_emails ce
    WHERE ce.campaign_id IN (SELECT id FROM wanted)
      AND ce.contact_id IS NOT NULL
      AND (ce.sent_at IS NOT NULL OR ce.status::text IN ('sent', 'delivered', 'opened', 'clicked', 'replied'))
      AND LOWER(BTRIM(COALESCE(ce.metadata->>'email_type', ce.metadata->>'emailType', ce.metadata->>'type',
                               ce.metadata->>'reply_type', ce.metadata->>'replyType', ''))) <> ALL(ARRAY[
        'reply', 'meeting_response', 'inquiry_response', 'information_response', 'neutral_follow_up',
        'not_interested_response', 'general_response', 'timeslots', 'booking_confirmation'])
    UNION ALL
    SELECT t.campaign_id, t.contact_id,
      CASE
        WHEN t.email_id IS NOT NULL AND t.email_id <> '' THEN 'message:' || t.email_id
        WHEN t.thread_id IS NOT NULL AND t.thread_id <> '' THEN
          'thread-sent:' || t.campaign_id::text || ':' || t.contact_id::text || ':' || t.thread_id || ':' || t.sent_at::text
        ELSE 'campaign-contact-sent:' || t.campaign_id::text || ':' || t.contact_id::text || ':' || t.sent_at::text
      END
    FROM public.tasks t
    WHERE t.organization_id = p_org_id
      AND t.task_type = 'review_draft'
      AND t.send_status = 'sent_success'
      AND t.sent_at IS NOT NULL
      AND t.contact_id IS NOT NULL
      AND t.campaign_id IS NOT NULL
      AND t.campaign_id IN (SELECT id FROM wanted)
      AND LOWER(BTRIM(COALESCE(t.metadata->>'email_type', t.metadata->>'emailType', t.metadata->>'type',
                               t.metadata->>'reply_type', t.metadata->>'replyType', ''))) <> ALL(ARRAY[
        'reply', 'meeting_response', 'inquiry_response', 'information_response', 'neutral_follow_up',
        'not_interested_response', 'general_response', 'timeslots', 'booking_confirmation'])
  ),
  email AS (
    SELECT s.campaign_id, count(DISTINCT s.dedup_key) AS sent, count(DISTINCT s.contact_id) AS reached
    FROM email_sends s GROUP BY s.campaign_id
  ),
  email_reached AS (
    SELECT DISTINCT s.campaign_id, s.contact_id FROM email_sends s
  ),
  -- Replied = reached people with a reply event on the campaign, so the list's rate never passes 100%.
  email_replied AS (
    SELECT r.campaign_id, count(*) AS replied
    FROM email_reached r
    WHERE EXISTS (
      SELECT 1 FROM public.email_reply_events e
      WHERE e.organization_id = p_org_id
        AND e.campaign_id = r.campaign_id
        AND e.contact_id = r.contact_id
    )
    GROUP BY r.campaign_id
  ),
  li_sends AS (
    SELECT a.campaign_id,
      count(DISTINCT COALESCE(a.counterpart_provider_id, a.recipient_provider_id)) FILTER (WHERE a.action_type = 'invitation') AS invited,
      count(DISTINCT COALESCE(a.counterpart_provider_id, a.recipient_provider_id)) FILTER (WHERE a.action_type = 'message') AS messaged
    FROM public.linkedin_action_log a
    WHERE a.organization_id = p_org_id
      AND a.success
      AND a.campaign_id IN (SELECT id FROM wanted)
      AND a.action_type IN ('invitation', 'message')
      AND COALESCE(a.counterpart_provider_id, a.recipient_provider_id) IS NOT NULL
    GROUP BY a.campaign_id
  ),
  li_accepted AS (
    SELECT cc.campaign_id, count(*) AS accepted
    FROM public.campaign_contacts cc
    WHERE cc.organization_id = p_org_id
      AND cc.campaign_id IN (SELECT id FROM wanted)
      AND cc.relation_state = 'connected'
    GROUP BY cc.campaign_id
  ),
  -- Threads with a reply, found once: counted origin, a person, and the time of the last inbound message.
  replied_threads AS (
    SELECT th.campaign_id, th.contact_id, th.linkedin_account_id,
           COALESCE(th.contact_id::text, 'li:' || th.counterpart_provider_id) AS person,
           MAX(m.occurred_at) AS last_reply_at
    FROM public.linkedin_threads th
    JOIN public.linkedin_messages m
      ON m.unipile_chat_id = th.unipile_chat_id
     AND m.organization_id = p_org_id
     AND m.direction = 'inbound'
    WHERE th.organization_id = p_org_id
      AND th.thread_origin IN ('sellton_outbound', 'campaign_inbound')
      AND (th.contact_id IS NOT NULL OR th.counterpart_provider_id IS NOT NULL)
    GROUP BY th.campaign_id, th.contact_id, th.linkedin_account_id, th.counterpart_provider_id
  ),
  -- A thread belongs to the campaign it carries; an untagged thread belongs to the campaigns its contact is enrolled
  -- in on the same LinkedIn account, for replies after that enrolment (a re-enrolment does not inherit old replies).
  wanted_contacts AS (
    SELECT cc.campaign_id, cc.contact_id, cc.linkedin_account_id, cc.created_at
    FROM public.campaign_contacts cc
    WHERE cc.campaign_id IN (SELECT id FROM wanted)
  ),
  li_replied AS (
    SELECT campaign_id, count(DISTINCT person) AS replied
    FROM (
      SELECT rt.campaign_id, rt.person
      FROM replied_threads rt
      WHERE rt.campaign_id IN (SELECT id FROM wanted)
      UNION
      SELECT wc.campaign_id, rt.person
      FROM replied_threads rt
      JOIN wanted_contacts wc
        ON wc.contact_id = rt.contact_id
       AND wc.linkedin_account_id IS NOT DISTINCT FROM rt.linkedin_account_id
       AND rt.last_reply_at >= wc.created_at
      WHERE rt.campaign_id IS NULL
    ) attached
    GROUP BY campaign_id
  )
  SELECT w.id,
    COALESCE(e.sent, 0), COALESCE(e.reached, 0), COALESCE(er.replied, 0),
    COALESCE(ls.invited, 0), COALESCE(la.accepted, 0), COALESCE(ls.messaged, 0), COALESCE(lr.replied, 0)
  FROM wanted w
  LEFT JOIN email e ON e.campaign_id = w.id
  LEFT JOIN email_replied er ON er.campaign_id = w.id
  LEFT JOIN li_sends ls ON ls.campaign_id = w.id
  LEFT JOIN li_accepted la ON la.campaign_id = w.id
  LEFT JOIN li_replied lr ON lr.campaign_id = w.id
$$;

REVOKE ALL ON FUNCTION public.campaign_channel_stats_v1(text, uuid[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.campaign_channel_stats_v1(text, uuid[]) TO service_role;

COMMENT ON FUNCTION public.campaign_channel_stats_v1(text, uuid[]) IS
  'KAN-322 D15: per-campaign email (sent, people reached, people replied) and LinkedIn (people invited, accepted, messaged, replied) numbers for the Plays list. All time, by person.';

-- Verification after apply:
-- SELECT proname FROM pg_proc WHERE proname IN ('dashboard_people_reply_rollup_v1', 'campaign_channel_stats_v1');
-- SELECT * FROM public.dashboard_people_reply_rollup_v1('<org>', now() - interval '7 days', now());
-- SELECT * FROM public.campaign_channel_stats_v1('<org>', ARRAY(SELECT id FROM public.campaigns WHERE organization_id = '<org>' LIMIT 20));
-- EXPLAIN ANALYZE SELECT * FROM public.dashboard_people_reply_rollup_v1('<largest org>', now() - interval '30 days', now());
