-- Dashboard exact-count rollups.
--
-- What changed:
--   - Adds dashboard_email_performance_rollup(), a DB-side aggregate for
--     dashboard email sent/opened/replied/bounced counters.
--   - Adds dashboard_summary_rollup(), a DB-side aggregate for primary
--     dashboard KPI counters that can exceed PostgREST row fetch limits.
--   - Adds a partial index for task-backed sent emails used as fallback source
--     when campaign_emails has not been written for a sent review draft.
--
-- Projects depending on this:
--   - selltonai /api/dashboard/intelligence reads this RPC for dashboard KPI
--     cards and Email Performance chart counters.
--
-- Application code update:
--   - Deploy with selltonai dashboard intelligence route changes.
--   - Response shapes are unchanged; only the source of dashboard counters changes.

CREATE INDEX IF NOT EXISTS idx_tasks_dashboard_email_sent_rollup
  ON public.tasks (organization_id, sent_at DESC, campaign_id, contact_id)
  WHERE task_type = 'review_draft'
    AND send_status = 'sent_success'
    AND sent_at IS NOT NULL
    AND campaign_id IS NOT NULL
    AND contact_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_campaigns_dashboard_summary_rollup
  ON public.campaigns (organization_id, user_id, status);

CREATE INDEX IF NOT EXISTS idx_contacts_dashboard_summary_rollup
  ON public.contacts (organization_id, pipeline_stage, created_at);

CREATE INDEX IF NOT EXISTS idx_tasks_dashboard_open_rollup
  ON public.tasks (organization_id, status, created_by_user_id, campaign_id)
  WHERE task_type IS NULL
    OR task_type <> 'email_generation_processing';

CREATE OR REPLACE FUNCTION public.dashboard_summary_rollup(
  p_org_id text,
  p_previous_start timestamptz,
  p_start timestamptz,
  p_end timestamptz,
  p_scope text DEFAULT 'all',
  p_user_id text DEFAULT NULL
)
RETURNS TABLE (
  active_campaigns bigint,
  paused_campaigns bigint,
  generated_leads bigint,
  previous_generated_leads bigint,
  pipeline_contacts bigint,
  open_tasks bigint,
  meetings_booked bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH scoped_campaigns AS (
    SELECT
      c.id,
      c.status::text AS status
    FROM public.campaigns c
    WHERE c.organization_id = p_org_id
      AND (p_scope <> 'mine' OR c.user_id = p_user_id)
  ),
  scoped_contacts AS (
    SELECT
      c.id,
      UPPER(BTRIM(COALESCE(c.pipeline_stage::text, ''))) AS stage_key,
      c.created_at
    FROM public.contacts c
    WHERE c.organization_id = p_org_id
      AND (
        p_scope <> 'mine'
        OR EXISTS (
          SELECT 1
          FROM public.campaign_emails ce
          JOIN scoped_campaigns sc ON sc.id = ce.campaign_id
          WHERE ce.organization_id = p_org_id
            AND ce.contact_id = c.id
        )
        OR EXISTS (
          SELECT 1
          FROM public.tasks t
          JOIN scoped_campaigns sc ON sc.id = t.campaign_id
          WHERE t.organization_id = p_org_id
            AND t.contact_id = c.id
        )
      )
  ),
  campaign_rollup AS (
    SELECT
      COUNT(*) FILTER (WHERE status = 'active') AS active_campaigns,
      COUNT(*) FILTER (WHERE status = 'paused') AS paused_campaigns
    FROM scoped_campaigns
  ),
  contact_rollup AS (
    SELECT
      COUNT(*) FILTER (
        WHERE stage_key = ANY(ARRAY[
          'LEAD',
          'APPOINTMENT_REQUESTED',
          'APPOINTMENT_SCHEDULED',
          'PRESENTATION_SCHEDULED',
          'CONTRACT_NEGOTIATIONS',
          'AGREEMENT_IN_PRINCIPLE',
          'CLOSED_WON',
          'REENGAGEMENT'
        ])
        AND created_at >= p_start
        AND created_at < p_end
      ) AS generated_leads,
      COUNT(*) FILTER (
        WHERE stage_key = ANY(ARRAY[
          'LEAD',
          'APPOINTMENT_REQUESTED',
          'APPOINTMENT_SCHEDULED',
          'PRESENTATION_SCHEDULED',
          'CONTRACT_NEGOTIATIONS',
          'AGREEMENT_IN_PRINCIPLE',
          'CLOSED_WON',
          'REENGAGEMENT'
        ])
        AND created_at >= p_previous_start
        AND created_at < p_start
      ) AS previous_generated_leads,
      COUNT(*) FILTER (
        WHERE stage_key = ANY(ARRAY[
          'LEAD',
          'APPOINTMENT_REQUESTED',
          'APPOINTMENT_SCHEDULED',
          'PRESENTATION_SCHEDULED',
          'CONTRACT_NEGOTIATIONS',
          'AGREEMENT_IN_PRINCIPLE',
          'CLOSED_WON',
          'REENGAGEMENT'
        ])
      ) AS pipeline_contacts,
      COUNT(*) FILTER (WHERE stage_key = 'APPOINTMENT_SCHEDULED') AS meetings_booked
    FROM scoped_contacts
  ),
  task_rollup AS (
    SELECT COUNT(*) AS open_tasks
    FROM public.tasks t
    LEFT JOIN public.contacts contact
      ON contact.id = t.contact_id
      AND contact.organization_id = t.organization_id
    LEFT JOIN public.campaigns task_campaign
      ON task_campaign.id = t.campaign_id
      AND task_campaign.organization_id = t.organization_id
    LEFT JOIN scoped_campaigns scoped_campaign
      ON scoped_campaign.id = t.campaign_id
    WHERE t.organization_id = p_org_id
      AND t.status::text IN ('pending', 'in_progress', 'scheduled')
      AND (t.task_type IS NULL OR t.task_type::text <> 'email_generation_processing')
      AND (contact.id IS NULL OR contact.do_not_contact IS DISTINCT FROM TRUE)
      AND (t.campaign_id IS NULL OR task_campaign.id IS NOT NULL)
      AND (task_campaign.status IS NULL OR task_campaign.status <> 'cancelled')
      AND (p_scope <> 'mine' OR t.created_by_user_id = p_user_id OR scoped_campaign.id IS NOT NULL)
  )
  SELECT
    COALESCE(campaign_rollup.active_campaigns, 0)::bigint AS active_campaigns,
    COALESCE(campaign_rollup.paused_campaigns, 0)::bigint AS paused_campaigns,
    COALESCE(contact_rollup.generated_leads, 0)::bigint AS generated_leads,
    COALESCE(contact_rollup.previous_generated_leads, 0)::bigint AS previous_generated_leads,
    COALESCE(contact_rollup.pipeline_contacts, 0)::bigint AS pipeline_contacts,
    COALESCE(task_rollup.open_tasks, 0)::bigint AS open_tasks,
    COALESCE(contact_rollup.meetings_booked, 0)::bigint AS meetings_booked
  FROM campaign_rollup, contact_rollup, task_rollup;
$$;

COMMENT ON FUNCTION public.dashboard_summary_rollup(text, timestamptz, timestamptz, timestamptz, text, text) IS
  'Exact dashboard summary KPI rollup. Used by selltonai to avoid PostgREST row limits on primary dashboard counters.';

REVOKE ALL ON FUNCTION public.dashboard_summary_rollup(text, timestamptz, timestamptz, timestamptz, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.dashboard_summary_rollup(text, timestamptz, timestamptz, timestamptz, text, text) FROM anon;
REVOKE ALL ON FUNCTION public.dashboard_summary_rollup(text, timestamptz, timestamptz, timestamptz, text, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.dashboard_summary_rollup(text, timestamptz, timestamptz, timestamptz, text, text) TO service_role;

CREATE OR REPLACE FUNCTION public.dashboard_email_performance_rollup(
  p_org_id text,
  p_start timestamptz,
  p_end timestamptz,
  p_campaign_ids uuid[] DEFAULT NULL
)
RETURNS TABLE (
  bucket_date date,
  campaign_id uuid,
  sent_count bigint,
  opened_count bigint,
  replied_count bigint,
  bounced_count bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH campaign_email_base AS (
    SELECT
      ce.id::text AS source_id,
      0 AS source_rank,
      ce.campaign_id,
      ce.contact_id,
      ce.status::text AS status,
      ce.sent_at,
      ce.opened_at,
      ce.replied_at,
      ce.bounced_at,
      ce.created_at,
      ce.message_id,
      ce.thread_id,
      CASE
        WHEN ce.message_id IS NOT NULL AND ce.message_id <> '' THEN 'message:' || ce.message_id
        WHEN ce.thread_id IS NOT NULL AND ce.thread_id <> '' AND ce.sent_at IS NOT NULL THEN
          'thread-sent:' || ce.campaign_id::text || ':' || ce.contact_id::text || ':' || ce.thread_id || ':' || ce.sent_at::text
        WHEN ce.sent_at IS NOT NULL THEN
          'campaign-contact-sent:' || ce.campaign_id::text || ':' || ce.contact_id::text || ':' || ce.sent_at::text
        ELSE 'campaign-email:' || ce.id::text
      END AS dedup_key
    FROM public.campaign_emails ce
    WHERE ce.organization_id = p_org_id
      AND (p_campaign_ids IS NULL OR ce.campaign_id = ANY(p_campaign_ids))
      AND (
        (COALESCE(ce.sent_at, ce.created_at) >= p_start AND COALESCE(ce.sent_at, ce.created_at) < p_end)
        OR (COALESCE(ce.opened_at, ce.sent_at, ce.created_at) >= p_start AND COALESCE(ce.opened_at, ce.sent_at, ce.created_at) < p_end)
        OR (COALESCE(ce.replied_at, ce.sent_at, ce.created_at) >= p_start AND COALESCE(ce.replied_at, ce.sent_at, ce.created_at) < p_end)
        OR (COALESCE(ce.bounced_at, ce.sent_at, ce.created_at) >= p_start AND COALESCE(ce.bounced_at, ce.sent_at, ce.created_at) < p_end)
      )
  ),
  sent_task_base AS (
    SELECT
      t.id::text AS source_id,
      1 AS source_rank,
      t.campaign_id,
      t.contact_id,
      'sent' AS status,
      t.sent_at,
      CASE
        WHEN ot.opened_at_text ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}' THEN ot.opened_at_text::timestamptz
        ELSE NULL::timestamptz
      END AS opened_at,
      NULL::timestamptz AS replied_at,
      NULL::timestamptz AS bounced_at,
      COALESCE(t.created_at, t.sent_at) AS created_at,
      t.email_id AS message_id,
      t.thread_id,
      CASE
        WHEN t.email_id IS NOT NULL AND t.email_id <> '' THEN 'message:' || t.email_id
        WHEN t.thread_id IS NOT NULL AND t.thread_id <> '' THEN
          'thread-sent:' || t.campaign_id::text || ':' || t.contact_id::text || ':' || t.thread_id || ':' || t.sent_at::text
        ELSE 'campaign-contact-sent:' || t.campaign_id::text || ':' || t.contact_id::text || ':' || t.sent_at::text
      END AS dedup_key
    FROM public.tasks t
    CROSS JOIN LATERAL (
      SELECT COALESCE(
        NULLIF(t.metadata #>> '{open_tracking,first_opened_at}', ''),
        NULLIF(t.metadata #>> '{open_tracking,last_opened_at}', '')
      ) AS opened_at_text
    ) ot
    WHERE t.organization_id = p_org_id
      AND t.task_type::text = 'review_draft'
      AND t.send_status = 'sent_success'
      AND t.sent_at IS NOT NULL
      AND t.sent_at >= p_start
      AND t.sent_at < p_end
      AND t.campaign_id IS NOT NULL
      AND t.contact_id IS NOT NULL
      AND (p_campaign_ids IS NULL OR t.campaign_id = ANY(p_campaign_ids))
  ),
  deduped_emails AS (
    SELECT DISTINCT ON (dedup_key)
      campaign_id,
      contact_id,
      status,
      sent_at,
      opened_at,
      replied_at,
      bounced_at,
      created_at
    FROM (
      SELECT * FROM campaign_email_base
      UNION ALL
      SELECT * FROM sent_task_base
    ) source_rows
    ORDER BY dedup_key, source_rank, source_id
  ),
  metric_events AS (
    SELECT
      DATE(COALESCE(sent_at, created_at) AT TIME ZONE 'UTC') AS bucket_date,
      campaign_id,
      1::bigint AS sent_count,
      0::bigint AS opened_count,
      0::bigint AS replied_count,
      0::bigint AS bounced_count
    FROM deduped_emails
    WHERE (sent_at IS NOT NULL OR status IN ('sent', 'delivered', 'opened', 'clicked', 'replied'))
      AND COALESCE(sent_at, created_at) >= p_start
      AND COALESCE(sent_at, created_at) < p_end

    UNION ALL

    SELECT
      DATE(COALESCE(opened_at, sent_at, created_at) AT TIME ZONE 'UTC') AS bucket_date,
      campaign_id,
      0::bigint,
      1::bigint,
      0::bigint,
      0::bigint
    FROM deduped_emails
    WHERE (opened_at IS NOT NULL OR status IN ('opened', 'clicked', 'replied'))
      AND COALESCE(opened_at, sent_at, created_at) >= p_start
      AND COALESCE(opened_at, sent_at, created_at) < p_end

    UNION ALL

    SELECT
      DATE(COALESCE(replied_at, sent_at, created_at) AT TIME ZONE 'UTC') AS bucket_date,
      campaign_id,
      0::bigint,
      0::bigint,
      1::bigint,
      0::bigint
    FROM deduped_emails
    WHERE (replied_at IS NOT NULL OR status = 'replied')
      AND COALESCE(replied_at, sent_at, created_at) >= p_start
      AND COALESCE(replied_at, sent_at, created_at) < p_end

    UNION ALL

    SELECT
      DATE(COALESCE(bounced_at, sent_at, created_at) AT TIME ZONE 'UTC') AS bucket_date,
      campaign_id,
      0::bigint,
      0::bigint,
      0::bigint,
      1::bigint
    FROM deduped_emails
    WHERE (bounced_at IS NOT NULL OR status = 'bounced')
      AND COALESCE(bounced_at, sent_at, created_at) >= p_start
      AND COALESCE(bounced_at, sent_at, created_at) < p_end
  )
  SELECT
    metric_events.bucket_date,
    metric_events.campaign_id,
    SUM(metric_events.sent_count)::bigint AS sent_count,
    SUM(metric_events.opened_count)::bigint AS opened_count,
    SUM(metric_events.replied_count)::bigint AS replied_count,
    SUM(metric_events.bounced_count)::bigint AS bounced_count
  FROM metric_events
  GROUP BY metric_events.bucket_date, metric_events.campaign_id
  ORDER BY metric_events.bucket_date ASC, metric_events.campaign_id ASC;
$$;

COMMENT ON FUNCTION public.dashboard_email_performance_rollup(text, timestamptz, timestamptz, uuid[]) IS
  'Exact dashboard email sent/opened/replied/bounced rollup by UTC date and campaign. Used by selltonai to avoid PostgREST row limits on large email volumes.';

REVOKE ALL ON FUNCTION public.dashboard_email_performance_rollup(text, timestamptz, timestamptz, uuid[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.dashboard_email_performance_rollup(text, timestamptz, timestamptz, uuid[]) FROM anon;
REVOKE ALL ON FUNCTION public.dashboard_email_performance_rollup(text, timestamptz, timestamptz, uuid[]) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.dashboard_email_performance_rollup(text, timestamptz, timestamptz, uuid[]) TO service_role;
