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
-- Performance: org-scoped through existing indexes (idx_tasks_dashboard_email_sent_rollup, email_reply_events
-- org+received, linkedin_threads org, linkedin_messages chat). STABLE, SECURITY INVOKER, service_role only.
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
    WHERE ce.organization_id = p_org_id
      AND ce.contact_id IS NOT NULL
      AND ce.campaign_id IN (SELECT id FROM scoped_campaigns)
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
      AND t.task_type::text = 'review_draft'
      AND t.send_status = 'sent_success'
      AND t.sent_at IS NOT NULL
      AND t.sent_at >= p_start
      AND t.sent_at < p_end
      AND t.contact_id IS NOT NULL
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
    SELECT e.contact_id, e.received_at
    FROM public.email_reply_events e
    WHERE e.organization_id = p_org_id
      AND e.contact_id IS NOT NULL
      AND e.campaign_id IN (SELECT id FROM scoped_campaigns)
      -- Every counted reply is inside the window (the rate's replies follow a first send that is inside it too).
      AND e.received_at >= p_start
      AND e.received_at < p_end
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
  li_reached AS (
    SELECT person, MIN(occurred_at) AS first_sent_at
    FROM li_messages
    WHERE direction = 'outbound'
    GROUP BY person
  )
  SELECT 'email'::text,
    (SELECT count(*) FROM email_reached),
    (SELECT count(DISTINCT contact_id) FROM email_replies),
    (SELECT count(*) FROM email_reached r
      WHERE EXISTS (SELECT 1 FROM email_replies e WHERE e.contact_id = r.contact_id AND e.received_at >= r.first_sent_at))
  UNION ALL
  SELECT 'linkedin'::text,
    (SELECT count(*) FROM li_reached),
    (SELECT count(DISTINCT person) FROM li_messages WHERE direction = 'inbound'),
    (SELECT count(*) FROM li_reached r
      WHERE EXISTS (SELECT 1 FROM li_messages m
                    WHERE m.person = r.person AND m.direction = 'inbound' AND m.occurred_at >= r.first_sent_at))
$$;

REVOKE ALL ON FUNCTION public.dashboard_people_reply_rollup_v1(text, timestamptz, timestamptz, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dashboard_people_reply_rollup_v1(text, timestamptz, timestamptz, text) TO service_role;

COMMENT ON FUNCTION public.dashboard_people_reply_rollup_v1(text, timestamptz, timestamptz, text) IS
  'KAN-322 D9: email and LinkedIn people reached / replied / reached-and-replied in a window, by person. Personal LinkedIn threads never count; email replies from email_reply_events (no OOO).';

-- 2. Plays list: one row per requested campaign of the organization, all time. Campaigns of other organizations
--    and unknown ids are not returned; a campaign with no activity returns zeros.
--    email_sent                outreach emails sent, de-duplicated like 359 (message id, then thread, then contact)
--    email_people_reached      distinct contacts sent outreach
--    email_people_replied      distinct contacts with a reply event on the campaign
--    linkedin_people_invited   distinct people with a successful invitation on the campaign (linkedin_action_log)
--    linkedin_people_accepted  campaign contacts whose relation is connected now (as the list shows today)
--    linkedin_people_messaged  distinct people with a successful message on the campaign
--    linkedin_people_replied   distinct people with an inbound message on a counted thread of the campaign: the thread
--                              carries the campaign, or its contact is a campaign contact on the same LinkedIn account
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
    SELECT ce.campaign_id, ce.contact_id,
      CASE
        WHEN ce.message_id IS NOT NULL AND ce.message_id <> '' THEN 'message:' || ce.message_id
        WHEN ce.thread_id IS NOT NULL AND ce.thread_id <> '' THEN
          'thread-sent:' || ce.campaign_id::text || ':' || ce.contact_id::text || ':' || ce.thread_id || ':' || COALESCE(ce.sent_at, ce.created_at)::text
        ELSE 'campaign-contact-sent:' || ce.campaign_id::text || ':' || ce.contact_id::text || ':' || COALESCE(ce.sent_at, ce.created_at)::text
      END AS dedup_key
    FROM public.campaign_emails ce
    WHERE ce.organization_id = p_org_id
      AND ce.campaign_id IN (SELECT id FROM wanted)
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
      AND t.task_type::text = 'review_draft'
      AND t.send_status = 'sent_success'
      AND t.sent_at IS NOT NULL
      AND t.contact_id IS NOT NULL
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
  email_replied AS (
    SELECT e.campaign_id, count(DISTINCT e.contact_id) AS replied
    FROM public.email_reply_events e
    WHERE e.organization_id = p_org_id
      AND e.campaign_id IN (SELECT id FROM wanted)
      AND e.contact_id IS NOT NULL
    GROUP BY e.campaign_id
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
  li_threads AS (
    SELECT w.id AS campaign_id, th.unipile_chat_id,
           COALESCE(th.contact_id::text, 'li:' || th.counterpart_provider_id) AS person
    FROM wanted w
    JOIN public.linkedin_threads th
      ON th.organization_id = p_org_id
     AND th.thread_origin IN ('sellton_outbound', 'campaign_inbound')
     AND (th.contact_id IS NOT NULL OR th.counterpart_provider_id IS NOT NULL)
     AND (
       th.campaign_id = w.id
       OR EXISTS (
         SELECT 1 FROM public.campaign_contacts cc
         WHERE cc.campaign_id = w.id
           AND cc.contact_id = th.contact_id
           AND cc.linkedin_account_id IS NOT DISTINCT FROM th.linkedin_account_id
       )
     )
  ),
  li_replied AS (
    SELECT t.campaign_id, count(DISTINCT t.person) AS replied
    FROM li_threads t
    WHERE EXISTS (
      SELECT 1 FROM public.linkedin_messages m
      WHERE m.unipile_chat_id = t.unipile_chat_id
        AND m.organization_id = p_org_id
        AND m.direction = 'inbound'
    )
    GROUP BY t.campaign_id
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
