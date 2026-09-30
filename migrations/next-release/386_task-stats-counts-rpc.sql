-- ============================================================
-- Migration: task-stats-counts-rpc (main: next-release/386, stage: next-release/386 — byte-identical)
-- Date:      2026-09-30
-- Purpose:   Count the Tasks page / home page task pills in ONE grouped query
--            instead of streaming every task row of the org to the BFF.
-- Projects:  selltonai-database/supabase (owner); reader: selltonai
--            GET /api/tasks/stats (src/app/api/tasks/stats/route.ts), which maps
--            the grouped rows onto its unchanged response keys.
-- Contract:  New read-only function only. No table, column, constraint, RLS,
--            trigger, cron or queue change. Safe to drop (the route falls back to
--            its row scan when the function is missing).
-- Depends:   public.tasks, public.contacts (do_not_contact), public.campaigns
--            (status), public.campaign_companies (status).
--
-- Why: /api/tasks/stats paged through up to 50,000 task rows in pages of 1,000,
-- each carrying metadata + conversation_summary JSON and three joins, and counted
-- them in JavaScript. The largest production org has 23,048 tasks (23 sequential
-- round trips per call); the home page makes five such calls on load, and each
-- OFFSET page re-reads the pages before it. This function returns a few dozen
-- rows (status x bucket x channel) computed where the data lives.
--
-- Semantics: mirrors src/lib/task-stats.ts + src/lib/task-visibility.ts +
-- src/lib/campaign-task-policy.ts on origin/main 2026-09-30, with ONE deliberate
-- change: review_draft approval is read from campaign_companies.status (the
-- authoritative, campaign-scoped rule the list route /api/tasks uses since
-- 2026-08-12) instead of the global companies.processing_status fallback, so the
-- pill counts and the list rows agree. Also as in the list route, a reply-sentiment
-- filter governs task type itself (p_task_type is ignored when it is set).
--   Hidden: task_type NULL or email_generation_processing; contact do_not_contact;
--   campaign_id set but campaign row missing; campaign status cancelled / deleted /
--   archived; review_draft without an approved campaign_companies row for its
--   (campaign, company); an OPEN (pending / scheduled / in_progress) company
--   verification, review draft or review reply whose campaign is not running for
--   that kind of work (outbound + verification: active / discovery_completed;
--   inbound replies: anything but cancelled; a campaign with no status: nothing).
--
-- Performance: org-scoped (idx_tasks_org_status / idx_tasks_org_type_status),
-- joins by primary key, approval as a hashed semi-join. STABLE, SECURITY INVOKER,
-- service_role only.
--
-- Rollback (safe):
--   DROP FUNCTION IF EXISTS public.task_stats_counts_v1(text, text, text, text, uuid, uuid, uuid, boolean, text, text, text);
-- ============================================================

CREATE OR REPLACE FUNCTION public.task_stats_counts_v1(
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
  p_assigned_user_id text DEFAULT NULL
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
      AND (p_task_type IS NULL OR p.reply_filter OR t.task_type::text = p_task_type)
      AND (NOT (coalesce(p_crm_only, false) AND p_channel IS NOT NULL AND p_task_type IS NULL AND NOT p.reply_filter)
           OR t.task_type::text IN ('review_draft', 'review_reply', 'manual_outreach', 'nurture_reminder', 'linkedin_connect'))
      AND (p_channel IS DISTINCT FROM 'linkedin' OR t.metadata ->> 'channel' = 'linkedin')
      AND (p_channel IS DISTINCT FROM 'email' OR t.metadata ->> 'channel' = 'email' OR t.metadata ->> 'channel' IS NULL)
      AND (p_priority IS NULL OR t.priority = p_priority)
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

REVOKE ALL ON FUNCTION public.task_stats_counts_v1(text, text, text, text, uuid, uuid, uuid, boolean, text, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.task_stats_counts_v1(text, text, text, text, uuid, uuid, uuid, boolean, text, text, text) TO service_role;

COMMENT ON FUNCTION public.task_stats_counts_v1(text, text, text, text, uuid, uuid, uuid, boolean, text, text, text) IS
  'Grouped task counts (status x bucket x channel) for GET /api/tasks/stats. Mirrors task-stats.ts / task-visibility.ts / campaign-task-policy.ts; review_draft approval from campaign_companies like /api/tasks.';

-- Verification after apply:
-- SELECT proname FROM pg_proc WHERE proname = 'task_stats_counts_v1';
-- SELECT * FROM public.task_stats_counts_v1('<org>') ORDER BY 1, 2, 3;
-- EXPLAIN ANALYZE SELECT * FROM public.task_stats_counts_v1('<largest org>');
