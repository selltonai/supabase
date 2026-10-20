-- ============================================================
-- Migration: restore-dashboard-summary-rollup (stage: next-release/410; stage-only repair, see "Promotion")
-- Date:      2026-10-20
-- Purpose:   Restore public.dashboard_summary_rollup on the stage DB. It is missing there (PostgREST PGRST202
--            "Could not find the function public.dashboard_summary_rollup(...) in the schema cache"), so stage's
--            GET /api/dashboard/intelligence logs "dashboard_summary_rollup unavailable or failed; using row-based
--            summary counts" on every load and runs the fallback path, not the one production runs.
-- Cause:     release_1.2.0/327_dashboard-email-performance-rollup.sql (2026-06-15) created both
--            dashboard_summary_rollup and dashboard_email_performance_rollup. 327 predates the migration runner
--            (the manifest starts at 344) and was never applied to the stage DB. release_1.3.0/359 re-creates
--            dashboard_email_performance_rollup and idx_tasks_dashboard_email_sent_rollup only, which is why the
--            email rollup exists on stage and the summary rollup does not. No migration on any branch drops or
--            renames dashboard_summary_rollup.
-- Projects:  selltonai-database/supabase (owner); reader: selltonai GET /api/dashboard/intelligence
--            (SUMMARY_ROLLUP_FUNCTION, service-role client, named args p_org_id, p_previous_start, p_start, p_end,
--            p_scope, p_user_id).
-- Contract:  The function, its COMMENT and its grants are 327's, byte for byte (CREATE OR REPLACE). The three
--            indexes 327 added for this function are re-created IF NOT EXISTS (they are likely missing on stage too,
--            for the same reason). No table, column, constraint, RLS, trigger, cron or queue change. Safe to drop.
-- Promotion: Production (and main) already have the function from 327. This file is stage-only: do not carry it
--            to main. If it ever is, it is a no-op there (identical body, IF NOT EXISTS indexes, same grants).
-- Locks:     The index builds take a SHARE lock on campaigns, contacts and tasks for their duration (stage-sized
--            tables). lock_timeout makes the file fail and roll back instead of queueing writers behind it.
-- Rollback:  DROP FUNCTION IF EXISTS public.dashboard_summary_rollup(text, timestamptz, timestamptz, timestamptz, text, text);
--            (the BFF falls back to row-based counts). Leave the indexes; they are 327's.
-- ============================================================

SET LOCAL lock_timeout = '10s';

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

-- Verify (read-only, on the stage DB after the run):
-- SELECT p.oid::regprocedure AS fn,
--        has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_exec,
--        has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth_exec,
--        has_function_privilege('service_role', p.oid, 'EXECUTE') AS service_exec
--   FROM pg_proc p WHERE p.proname = 'dashboard_summary_rollup';
--   -- expect one row: dashboard_summary_rollup(text,timestamp with time zone,...,text,text), false, false, true
-- SELECT to_regclass('public.idx_campaigns_dashboard_summary_rollup'),
--        to_regclass('public.idx_contacts_dashboard_summary_rollup'),
--        to_regclass('public.idx_tasks_dashboard_open_rollup');  -- expect three non-null names
-- SELECT * FROM public.dashboard_summary_rollup('<org>', now() - interval '60 days', now() - interval '30 days', now());
--   -- expect one row of seven bigint counters
