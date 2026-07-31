-- Canonical inbound email-reply projection for dashboard analytics.
--
-- Producer:
--   selltonai-modal incoming-email webhook (service role)
-- Consumer:
--   selltonai /api/dashboard/intelligence via dashboard_email_performance_rollup()
--
-- The projection intentionally stores identifiers and classification metadata
-- only. Email addresses, subjects, snippets, and bodies remain in their owning
-- systems and must never be copied into this analytics table.

CREATE TABLE IF NOT EXISTS public.email_reply_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL,
  dedup_key text NOT NULL,
  email_id text NOT NULL,
  account_id text,
  thread_id text,
  contact_id uuid,
  campaign_id uuid,
  received_at timestamptz NOT NULL,
  classification text NOT NULL,
  relevance text,
  source text NOT NULL DEFAULT 'gmail_webhook',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT email_reply_events_org_dedup_unique UNIQUE (organization_id, dedup_key)
);

COMMENT ON TABLE public.email_reply_events IS
  'Idempotent, PII-minimized projection of countable inbound email replies for campaign analytics.';
COMMENT ON COLUMN public.email_reply_events.dedup_key IS
  'Stable producer key. Gmail events use gmail:<email_id> within an organization.';

CREATE INDEX IF NOT EXISTS idx_email_reply_events_org_received
  ON public.email_reply_events (organization_id, received_at DESC);

CREATE INDEX IF NOT EXISTS idx_email_reply_events_org_campaign_received
  ON public.email_reply_events (organization_id, campaign_id, received_at DESC)
  WHERE campaign_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_email_reply_events_org_thread_received
  ON public.email_reply_events (organization_id, thread_id, received_at DESC)
  WHERE thread_id IS NOT NULL;

ALTER TABLE public.email_reply_events ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.email_reply_events FROM PUBLIC;
REVOKE ALL ON TABLE public.email_reply_events FROM anon;
REVOKE ALL ON TABLE public.email_reply_events FROM authenticated;
GRANT ALL ON TABLE public.email_reply_events TO service_role;

-- Stage missed release 1.2.0 migration 327. Recreate the supporting index here
-- so this migration is independently deployable and the task fallback stays fast.
CREATE INDEX IF NOT EXISTS idx_tasks_dashboard_email_sent_rollup
  ON public.tasks (organization_id, sent_at DESC, campaign_id, contact_id)
  WHERE task_type = 'review_draft'
    AND send_status = 'sent_success'
    AND sent_at IS NOT NULL
    AND campaign_id IS NOT NULL
    AND contact_id IS NOT NULL;

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
      AND LOWER(BTRIM(COALESCE(
        ce.metadata->>'email_type',
        ce.metadata->>'emailType',
        ce.metadata->>'type',
        ce.metadata->>'reply_type',
        ce.metadata->>'replyType',
        ''
      ))) <> ALL(ARRAY[
        'reply',
        'meeting_response',
        'inquiry_response',
        'information_response',
        'neutral_follow_up',
        'not_interested_response',
        'general_response',
        'timeslots',
        'booking_confirmation'
      ])
      AND (
        (COALESCE(ce.sent_at, ce.created_at) >= p_start AND COALESCE(ce.sent_at, ce.created_at) < p_end)
        OR (COALESCE(ce.opened_at, ce.sent_at, ce.created_at) >= p_start AND COALESCE(ce.opened_at, ce.sent_at, ce.created_at) < p_end)
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
        WHEN open_tracking.opened_at_text ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}' THEN open_tracking.opened_at_text::timestamptz
        ELSE NULL::timestamptz
      END AS opened_at,
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
    ) open_tracking
    WHERE t.organization_id = p_org_id
      AND t.task_type::text = 'review_draft'
      AND t.send_status = 'sent_success'
      AND t.sent_at IS NOT NULL
      AND t.sent_at >= p_start
      AND t.sent_at < p_end
      AND t.campaign_id IS NOT NULL
      AND t.contact_id IS NOT NULL
      AND (p_campaign_ids IS NULL OR t.campaign_id = ANY(p_campaign_ids))
      AND LOWER(BTRIM(COALESCE(
        t.metadata->>'email_type',
        t.metadata->>'emailType',
        t.metadata->>'type',
        t.metadata->>'reply_type',
        t.metadata->>'replyType',
        ''
      ))) <> ALL(ARRAY[
        'reply',
        'meeting_response',
        'inquiry_response',
        'information_response',
        'neutral_follow_up',
        'not_interested_response',
        'general_response',
        'timeslots',
        'booking_confirmation'
      ])
  ),
  deduped_outreach_emails AS (
    SELECT DISTINCT ON (dedup_key)
      campaign_id,
      status,
      sent_at,
      opened_at,
      bounced_at,
      created_at
    FROM (
      SELECT * FROM campaign_email_base
      UNION ALL
      SELECT * FROM sent_task_base
    ) source_rows
    ORDER BY dedup_key, source_rank, source_id
  ),
  reply_candidates AS (
    SELECT
      ce.campaign_id,
      COALESCE(ce.reply_received_at, ce.replied_at, ce.sent_at, ce.created_at) AS replied_at,
      CASE
        WHEN ce.thread_id IS NOT NULL AND ce.thread_id <> '' THEN
          'thread:' || ce.campaign_id::text || ':' || ce.thread_id
        WHEN ce.message_id IS NOT NULL AND ce.message_id <> '' THEN
          'message:' || ce.campaign_id::text || ':' || ce.message_id
        ELSE 'contact:' || ce.campaign_id::text || ':' || ce.contact_id::text
      END AS conversion_key
    FROM public.campaign_emails ce
    WHERE ce.organization_id = p_org_id
      AND ce.campaign_id IS NOT NULL
      AND (p_campaign_ids IS NULL OR ce.campaign_id = ANY(p_campaign_ids))
      AND (ce.replied_at IS NOT NULL OR ce.reply_received_at IS NOT NULL OR ce.status::text = 'replied')

    UNION ALL

    SELECT
      reply_event.campaign_id,
      reply_event.received_at AS replied_at,
      CASE
        WHEN reply_event.thread_id IS NOT NULL AND reply_event.thread_id <> '' THEN
          'thread:' || reply_event.campaign_id::text || ':' || reply_event.thread_id
        WHEN reply_event.contact_id IS NOT NULL THEN
          'contact:' || reply_event.campaign_id::text || ':' || reply_event.contact_id::text
        ELSE 'message:' || reply_event.campaign_id::text || ':' || reply_event.email_id
      END AS conversion_key
    FROM public.email_reply_events reply_event
    WHERE reply_event.organization_id = p_org_id
      AND reply_event.campaign_id IS NOT NULL
      AND (p_campaign_ids IS NULL OR reply_event.campaign_id = ANY(p_campaign_ids))
  ),
  first_replies AS (
    SELECT
      reply_candidates.campaign_id,
      reply_candidates.conversion_key,
      MIN(reply_candidates.replied_at) AS replied_at
    FROM reply_candidates
    WHERE reply_candidates.replied_at IS NOT NULL
    GROUP BY reply_candidates.campaign_id, reply_candidates.conversion_key
  ),
  metric_events AS (
    SELECT
      DATE(COALESCE(sent_at, created_at) AT TIME ZONE 'UTC') AS bucket_date,
      campaign_id,
      1::bigint AS sent_count,
      0::bigint AS opened_count,
      0::bigint AS replied_count,
      0::bigint AS bounced_count
    FROM deduped_outreach_emails
    WHERE (sent_at IS NOT NULL OR status IN ('sent', 'delivered', 'opened', 'clicked', 'replied'))
      AND COALESCE(sent_at, created_at) >= p_start
      AND COALESCE(sent_at, created_at) < p_end

    UNION ALL

    SELECT
      DATE(COALESCE(opened_at, sent_at, created_at) AT TIME ZONE 'UTC'),
      campaign_id,
      0::bigint,
      1::bigint,
      0::bigint,
      0::bigint
    FROM deduped_outreach_emails
    WHERE (opened_at IS NOT NULL OR status IN ('opened', 'clicked', 'replied'))
      AND COALESCE(opened_at, sent_at, created_at) >= p_start
      AND COALESCE(opened_at, sent_at, created_at) < p_end

    UNION ALL

    SELECT
      DATE(first_replies.replied_at AT TIME ZONE 'UTC'),
      first_replies.campaign_id,
      0::bigint,
      0::bigint,
      1::bigint,
      0::bigint
    FROM first_replies
    WHERE first_replies.replied_at >= p_start
      AND first_replies.replied_at < p_end

    UNION ALL

    SELECT
      DATE(COALESCE(bounced_at, sent_at, created_at) AT TIME ZONE 'UTC'),
      campaign_id,
      0::bigint,
      0::bigint,
      0::bigint,
      1::bigint
    FROM deduped_outreach_emails
    WHERE (bounced_at IS NOT NULL OR status = 'bounced')
      AND COALESCE(bounced_at, sent_at, created_at) >= p_start
      AND COALESCE(bounced_at, sent_at, created_at) < p_end
  )
  SELECT
    metric_events.bucket_date,
    metric_events.campaign_id,
    SUM(metric_events.sent_count)::bigint,
    SUM(metric_events.opened_count)::bigint,
    SUM(metric_events.replied_count)::bigint,
    SUM(metric_events.bounced_count)::bigint
  FROM metric_events
  GROUP BY metric_events.bucket_date, metric_events.campaign_id
  ORDER BY metric_events.bucket_date ASC, metric_events.campaign_id ASC;
$$;

COMMENT ON FUNCTION public.dashboard_email_performance_rollup(text, timestamptz, timestamptz, uuid[]) IS
  'Exact dashboard outbound sent/open/bounce and first inbound reply conversion rollup by UTC date and campaign.';

REVOKE ALL ON FUNCTION public.dashboard_email_performance_rollup(text, timestamptz, timestamptz, uuid[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.dashboard_email_performance_rollup(text, timestamptz, timestamptz, uuid[]) FROM anon;
REVOKE ALL ON FUNCTION public.dashboard_email_performance_rollup(text, timestamptz, timestamptz, uuid[]) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.dashboard_email_performance_rollup(text, timestamptz, timestamptz, uuid[]) TO service_role;
