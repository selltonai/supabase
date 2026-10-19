-- ============================================================
-- Migration: task-stats-counts-v2 (stage: next-release/408; KAN-322 FR-B5e, D88)
-- Date:      2026-10-19
-- Purpose:   The task counts with exactly the task list's rule, so the Tasks header, tabs, the menu badge and the
--            dashboard's queue (D69) can never disagree with the list (GET /api/tasks).
-- Projects:  selltonai-database/supabase (owner); reader: selltonai GET /api/tasks/stats
--            (src/app/api/tasks/stats/route.ts), which calls v2 and falls back to v1, logged, while 408 is absent.
-- Contract:  New read-only function only; task_stats_counts_v1 (386) is left in place for that fallback and for the
--            production line until the promotion. No table, column, index, RLS, trigger, cron or queue change.
--            Safe to drop (the route falls back to v1).
-- Depends:   public.tasks (due_date), public.contacts, public.campaigns, public.campaign_companies (as 386).
--
-- v2 = v1 (386) with the three places where v1's rule was not the list's:
--   1. Type under a reply filter. List: a reply filter drops the type only when it is review_draft or review_reply;
--      any other type is kept. v1 dropped every type.
--   2. A channel without a type, outside the CRM source. List: review_draft and review_reply only (FR-B5e makes the
--      list's rule hold under a reply filter too: a reply on the Emails or LinkedIn pill is a draft or reply, the set
--      the pill counts). v1 counted every type of that channel (its 'other' bucket still reached totalTasks).
--   3. Due bounds (p_due_from inclusive, p_due_before exclusive, on tasks.due_date). List: FR-C4d's due_from /
--      due_before. v1 had none, so the Tasks tabs showed "-" under ?due=.
-- Everything else is v1's, unchanged: the hidden rows (do not contact; a missing, cancelled, deleted or archived
-- play; a review draft without an approved campaign_companies pair; open work of a play that is not running for it),
-- the reply clause (review_reply or metadata.email_type = 'reply'), the sentiment sets, the buckets and channels.
--
-- Performance: as 386 (org-scoped, joins by primary key, approval as a hashed semi-join); the due bounds can use
-- idx_tasks_org_due_date. STABLE, SECURITY INVOKER, service_role only.
--
-- Rollback (safe): migrations/next-release/rollback/408_task-stats-counts-v2.rollback.sql
--   DROP FUNCTION IF EXISTS public.task_stats_counts_v2(text, text, text, text, uuid, uuid, uuid, boolean, text, text, text, timestamptz, timestamptz);
-- ============================================================

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
           OR t.task_type::text IN ('review_draft', 'review_reply'))
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
  'Grouped task counts (status x bucket x channel) for GET /api/tasks/stats with the task list''s rule (api/tasks): type under a reply filter, review types for a channel pill, due bounds. v1 (386) stays as the fallback.';

-- Verification after apply:
-- SELECT proname, pg_get_function_identity_arguments(oid) FROM pg_proc WHERE proname = 'task_stats_counts_v2';
-- SELECT has_function_privilege('anon', 'public.task_stats_counts_v2(text, text, text, text, uuid, uuid, uuid, boolean, text, text, text, timestamptz, timestamptz)', 'EXECUTE');  -- false
-- SELECT * FROM public.task_stats_counts_v2('<org>') ORDER BY 1, 2, 3;  -- equals v1 for a call without type, channel or due
-- EXPLAIN ANALYZE SELECT * FROM public.task_stats_counts_v2('<largest org>', p_due_before => now());
