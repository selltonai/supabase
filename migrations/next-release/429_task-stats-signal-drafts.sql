-- ============================================================
-- Migration: 429_task-stats-signal-drafts
-- Date:      2026-11-11
-- Purpose:   Brain signals fixes round 3, L5 (Borce 2026-11-11 "Yes, both"): a deal follow-up drafted from a signal
--            (task_type nurture_reminder with metadata.signal_draft true) is listed under its channel's tab (Emails
--            or LinkedIn) as well, and that tab counts it. task_stats_counts_v2 changes in two places only:
--              1. A channel without a type, outside the CRM source, counts these drafts besides review drafts and
--                 replies (the list's rule in selltonai GET /api/tasks from the same release).
--              2. Outside the CRM source they get the bucket 'signal_draft' (they were 'other'), so the app adds them
--                 to their channel's tab and never to the review count. The CRM source keeps them under 'review'.
--            Every other nurture_reminder, manual_outreach and linkedin_connect stays out of the channel tabs, as
--            408 left them (production fix 2026-10-01). A reply filter is as before: replies only.
-- Projects:  selltonai-database/supabase (owner); reader: selltonai GET /api/tasks/stats
--            (src/app/api/tasks/stats/route.ts, src/lib/task-stats.ts aggregateTaskStatsFromGroups).
-- Contract:  Same name, arguments and result columns as 408, so CREATE OR REPLACE keeps every caller working. The new
--            bucket value is safe for the app on stage before its PR lands: the current app counts a bucket it does not
--            know in totalTasks and the status totals, as it counted 'other' (plus a stray 'undefined...Tasks' key no
--            screen reads), so its tabs stay as today until the app PR merges. Checked against selltonai stage
--            3b3b1a977, src/lib/task-stats.ts addTasksToStats.
--            Merge order: this PR, then the Modal PR of fix/signals-fixes-3, then the app PR
--            (feat/signals-label-filter).
-- Depends:   public.task_stats_counts_v2 (408), public.tasks, public.contacts, public.campaigns,
--            public.campaign_companies.
-- Rollback:  rollback/429_task-stats-signal-drafts.rollback.sql (restores 408's body).
-- ============================================================

SET LOCAL lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.task_stats_counts_v2(
  p_organization_id text,
  p_status text DEFAULT NULL,
  p_task_type text DEFAULT NULL,
  p_priority text DEFAULT NULL,
  p_campaign_id uuid DEFAULT NULL,
  p_contact_id uuid DEFAULT NULL,
  p_company_id uuid DEFAULT NULL,
  p_crm_only boolean DEFAULT false,
  p_channel text DEFAULT NULL,
  p_reply_sentiment text DEFAULT NULL,
  p_assigned_user_id text DEFAULT NULL,
  p_due_from timestamptz DEFAULT NULL,
  p_due_before timestamptz DEFAULT NULL
)
RETURNS TABLE(status text, bucket text, channel text, tasks bigint, with_company bigint, with_campaign bigint, with_contact bigint)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path = public
AS $$
  WITH params AS (
    SELECT coalesce(p_reply_sentiment IN ('replies_all', 'replies_positive', 'replies_neutral', 'replies_negative'), false) AS reply_filter
  ),
  scoped AS (
    SELECT
      t.status::text AS status,
      t.task_type::text AS task_type,
      t.company_id,
      t.campaign_id,
      t.contact_id,
      t.metadata,
      t.conversation_summary,
      c.id IS NOT NULL AS has_campaign,
      c.status::text AS campaign_status,
      lower(btrim(coalesce(c.status::text, ''))) AS campaign_status_norm
    FROM public.tasks t
    CROSS JOIN params p
    LEFT JOIN public.campaigns c ON c.id = t.campaign_id
    LEFT JOIN public.contacts ct ON ct.id = t.contact_id
    WHERE t.organization_id = p_organization_id
      AND t.task_type <> 'email_generation_processing'
      AND (NOT coalesce(p_crm_only, false) OR t.deal_id IS NOT NULL)
      AND (p_assigned_user_id IS NULL OR t.assigned_to_user_id = p_assigned_user_id)
      AND (p_status IS NULL OR t.status::text = p_status)
      -- The list's type rule (api/tasks/route.ts): under a reply filter only a review type gives way to the reply
      -- clause; any other type is kept (v1 dropped every type, so Companies or Meetings + a reply filter counted every
      -- reply while the list showed none).
      AND (p_task_type IS NULL
           OR (p.reply_filter AND p_task_type IN ('review_draft', 'review_reply'))
           OR t.task_type::text = p_task_type)
      AND (NOT (coalesce(p_crm_only, false) AND p_channel IS NOT NULL AND p_task_type IS NULL AND NOT p.reply_filter)
           OR t.task_type::text IN ('review_draft', 'review_reply', 'manual_outreach', 'nurture_reminder', 'linkedin_connect'))
      -- The list's channel pill outside the CRM source lists review drafts and replies only, with or without a reply
      -- filter (v1 had no such rule).
      AND (coalesce(p_crm_only, false) OR p_channel IS NULL OR p_task_type IS NOT NULL
           OR t.task_type::text IN ('review_draft', 'review_reply')
           -- 429 (L5): a deal follow-up drafted from a signal is listed under its channel too.
           OR (t.task_type::text = 'nurture_reminder' AND t.metadata -> 'signal_draft' = 'true'::jsonb))
      AND (p_channel IS DISTINCT FROM 'linkedin' OR t.metadata ->> 'channel' = 'linkedin')
      AND (p_channel IS DISTINCT FROM 'email' OR t.metadata ->> 'channel' = 'email' OR t.metadata ->> 'channel' IS NULL)
      AND (p_priority IS NULL OR t.priority = p_priority)
      -- The list's due bounds (FR-C4d's dashboard links): from inclusive, before exclusive; a task with no due date is
      -- outside any bound.
      AND (p_due_from IS NULL OR t.due_date >= p_due_from)
      AND (p_due_before IS NULL OR t.due_date < p_due_before)
      AND (p_contact_id IS NULL OR t.contact_id = p_contact_id)
      AND (p_campaign_id IS NULL OR t.campaign_id = p_campaign_id)
      AND (p_company_id IS NULL OR t.company_id = p_company_id)
      AND (NOT p.reply_filter OR t.task_type = 'review_reply' OR t.metadata ->> 'email_type' = 'reply')
      -- task-visibility: do-not-contact, missing or hidden campaign
      AND ct.do_not_contact IS DISTINCT FROM true
      AND NOT (t.campaign_id IS NOT NULL AND c.id IS NULL)
      AND NOT (c.status IS NOT NULL AND lower(c.status::text) IN ('cancelled', 'deleted', 'archived'))
  ),
  visible AS (
    SELECT s.*,
      CASE
        WHEN s.task_type = 'company_verification' THEN 'company_verification'
        WHEN s.task_type = 'review_reply' THEN 'inbound_reply'
        WHEN jsonb_typeof(s.metadata -> 'email_type') = 'string'
             AND lower(btrim(s.metadata ->> 'email_type')) IN ('reply', 'meeting_response', 'inquiry_response',
               'information_response', 'neutral_follow_up', 'not_interested_response', 'general_response',
               'timeslots', 'booking_confirmation') THEN 'inbound_reply'
        ELSE 'outbound_message'
      END AS work_kind
    FROM scoped s
    WHERE
      -- review_draft needs an approved (campaign, company) pair, like the list route
      (s.task_type <> 'review_draft' OR EXISTS (
        SELECT 1 FROM public.campaign_companies cc
        WHERE cc.organization_id = p_organization_id
          AND cc.campaign_id = s.campaign_id
          AND cc.company_id = s.company_id
          AND cc.status::text = 'approved'
      ))
  ),
  counted AS (
    SELECT v.*,
      coalesce(
        CASE WHEN jsonb_typeof(v.metadata -> 'sentiment') = 'string'
             THEN nullif(nullif(upper(btrim(v.metadata ->> 'sentiment', E' \t\n\r')), ''), 'UNKNOWN') END,
        CASE WHEN jsonb_typeof(v.conversation_summary -> 'intents' -> 'sentiment') = 'string'
             THEN nullif(nullif(upper(btrim(v.conversation_summary -> 'intents' ->> 'sentiment', E' \t\n\r')), ''), 'UNKNOWN') END,
        CASE WHEN v.metadata -> 'soft_no' = 'true'::jsonb THEN 'NEUTRAL' END,
        CASE WHEN jsonb_typeof(v.metadata -> 'reply_type') = 'string'
              AND v.metadata ->> 'reply_type' = 'not_interested_response' THEN 'NEGATIVE' END,
        'UNKNOWN'
      ) AS sentiment
    FROM visible v
    WHERE NOT (
      v.has_campaign
      AND v.task_type IN ('company_verification', 'review_draft', 'review_reply')
      AND v.status IN ('pending', 'scheduled', 'in_progress')
      AND NOT (
        CASE
          WHEN v.campaign_status_norm = '' THEN false
          WHEN v.work_kind = 'inbound_reply' THEN v.campaign_status_norm <> 'cancelled'
          ELSE v.campaign_status_norm IN ('active', 'discovery_completed')
        END
      )
    )
  )
  SELECT
    k.status,
    CASE
      WHEN k.task_type IN ('review_draft', 'review_reply')
        OR (coalesce(p_crm_only, false) AND k.task_type IN ('review_draft', 'review_reply', 'manual_outreach', 'nurture_reminder', 'linkedin_connect'))
        THEN 'review'
      -- 429 (L5): outside the CRM source (the CRM source made it 'review' above), its channel tab only.
      WHEN k.task_type = 'nurture_reminder' AND k.metadata -> 'signal_draft' = 'true'::jsonb THEN 'signal_draft'
      WHEN k.task_type = 'call' THEN 'call'
      WHEN k.task_type = 'meeting' THEN 'meeting'
      WHEN k.task_type = 'company_verification' THEN 'company_verification'
      ELSE 'other'
    END AS bucket,
    CASE WHEN k.metadata ->> 'channel' = 'linkedin' THEN 'linkedin' ELSE 'email' END AS channel,
    count(*) AS tasks,
    count(k.company_id) AS with_company,
    count(k.campaign_id) AS with_campaign,
    count(k.contact_id) AS with_contact
  FROM counted k
  CROSS JOIN params p
  WHERE NOT p.reply_filter
     OR p_reply_sentiment = 'replies_all'
     OR (p_reply_sentiment = 'replies_positive' AND k.sentiment IN ('POSITIVE', 'VERY_POSITIVE', 'INTERESTED', 'QUALIFIED_TO_BUY', 'DECISION_MAKER_BOUGHT_IN'))
     OR (p_reply_sentiment = 'replies_neutral' AND k.sentiment IN ('NEUTRAL', 'UNKNOWN'))
     OR (p_reply_sentiment = 'replies_negative' AND k.sentiment IN ('NEGATIVE', 'VERY_NEGATIVE', 'NOT_INTERESTED'))
  GROUP BY 1, 2, 3
$$;

REVOKE ALL ON FUNCTION public.task_stats_counts_v2(text, text, text, text, uuid, uuid, uuid, boolean, text, text, text, timestamptz, timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.task_stats_counts_v2(text, text, text, text, uuid, uuid, uuid, boolean, text, text, text, timestamptz, timestamptz) TO service_role;

COMMENT ON FUNCTION public.task_stats_counts_v2(text, text, text, text, uuid, uuid, uuid, boolean, text, text, text, timestamptz, timestamptz) IS
  'Grouped task counts (status x bucket x channel) for GET /api/tasks/stats with the task list''s rule (api/tasks): type under a reply filter, review types and deal signal drafts (bucket signal_draft, 429) for a channel pill, due bounds. v1 (386) stays as the fallback.';

-- Verification after apply:
-- SELECT md5(prosrc) FROM pg_proc WHERE proname = 'task_stats_counts_v2';  -- changed from 408's 84fc83ecc0272c26747aecfb82b96cc6
-- SELECT has_function_privilege('anon', 'public.task_stats_counts_v2(text, text, text, text, uuid, uuid, uuid, boolean, text, text, text, timestamptz, timestamptz)', 'EXECUTE');  -- false
-- SELECT * FROM public.task_stats_counts_v2('<org with a signal draft>') WHERE bucket = 'signal_draft';
-- SELECT * FROM public.task_stats_counts_v2('<org with a signal draft>', p_channel => 'email');  -- includes the drafts
