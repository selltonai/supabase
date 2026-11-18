-- ============================================================
-- Migration: 423_backoffice-cs-agent-facts (stage: next-release/423; renumber at promotion if 423 is taken)
-- Date:      2026-11-11
-- Purpose:   The backoffice's customer-success agent, its reads (facts). Two read-only functions and two columns.
--            1. backoffice_cs_segment_inputs_v1(): one row per organization with deleted = false, every count
--               aggregated in SQL. The backoffice classifies each workspace into a lifecycle stage from it.
--            2. backoffice_cs_workspace_facts_v1(p_org text): one workspace's facts as one jsonb object
--               (aggregates and the workspace's own data). segment and health_score are null here: the backoffice
--               computes them. The object never holds a prospect's name, a prospect's email address or a reply
--               body: no contact, message body or reply text is read.
--            3. user_profiles.last_seen_at (timestamptz): when the person was last seen in the workspace. Written
--               at most hourly by the web and, later, the phone; nothing writes it in this file.
--            4. user_profiles.consent_marketing_at (timestamptz): when the person agreed to marketing email from
--               Sellton; NULL = no consent. Nothing writes it in this file.
-- Projects:  selltonai-database/supabase (owner). backoffice is the only caller of both functions.
--            selltonai and the mobile service: writers of the two columns in their own releases; until then the
--            columns stay NULL and the functions read them as "never seen" and "no consent".
--            selltonai-modal and the engine: none.
-- Contract:  Additive. Two new functions and two nullable columns on user_profiles; no other object changes, no
--            index is added, no row is written. Both functions are STABLE, SECURITY INVOKER, service role only
--            (anon and authenticated cannot execute them). The backoffice treats a missing function as "not
--            deployed" and builds the same rows from the tables, so this file and the backoffice build can ship
--            in either order. Application code: none must ship together with this file.
-- Depends:   422 (cs_recommendations), organization (302, 324, 379, 382), organization_settings (49, 409, 414),
--            user_organizations (246, 403), user_profiles (228/247, 230), org_seats (306, 316, 382),
--            billing_customers (243, 371, 382), billing_credits (382), billing_invoices (243),
--            discount_codes and discount_code_redemptions (304, 312), usage (123), campaigns (38, 81),
--            tasks (38, 176), campaign_emails (38, 281), linkedin_accounts (254), linkedin_action_log (255),
--            organization_files (28), onboarding_research (300, 313), onboarding_reengagement_sends (308),
--            email_broadcast_sends (340), customer_requests (391), backoffice_org_notes (341),
--            support_workspace_sessions (316).
-- Rollback:  rollback/423_backoffice-cs-agent-facts.rollback.sql
--
-- Definitions (both functions; windows roll back from now()):
--   Member          a user_organizations row of the workspace.
--   Human action    a task completed by a member, a task created by a member, a play created (campaigns, status
--                   not cancelled), a file uploaded (organization_files.uploaded_by not 'api' or 'system'). A task
--                   whose completed_by_user_id or created_by_user_id is not a member of the workspace (Autonomous
--                   and the engine write 'api' or NULL; support staff are not members) is not a human action.
--                   Activity window: 45 days; older actions read as NULL.
--   Approval        a task completed by a member (completed_at). Last 7 days, and the 7 days before that.
--   Pending         tasks in status pending (drafts waiting for a person).
--   Meeting         a task of type meeting, by created_at.
--   Email sent      campaign_emails.sent_at; reply: campaign_emails.replied_at; positive reply: a reply whose
--                   classification intent is positive_intent.
--   LinkedIn sent   linkedin_action_log, a successful invitation or message.
--   Our own email   to the customer: onboarding_reengagement_sends (the lifecycle chase), email_broadcast_sends with
--                   status sent, and cs_recommendations of kind email that were executed; last 30 days. The
--                   customer's reply: cs_recommendations.outcome.replied_at of those email proposals.
--   Usage           usage.sellton_cost.
--
-- Performance: the rollup reads each source table once, grouped by organization_id, and joins the groups to
--   organization (no per-workspace subquery). Windowed reads use the existing indexes: idx_tasks_org_completed,
--   idx_tasks_org_created and idx_tasks_org_status, idx_campaign_emails_sent_at and idx_campaign_emails_replied_at,
--   idx_usage_org_created_desc, cs_recommendations_org_idx. The tasks read is one pass over the tasks pending or
--   touched in the last 45 days. The facts read is filtered by organization_id on every table.
-- ============================================================

-- user_profiles is read on every request; fail fast instead of queueing behind a long transaction (the runner rolls
-- the file back and it can be re-run).
SET LOCAL lock_timeout = '10s';

-- 1. Two columns on user_profiles (one row per person and workspace) ---------------------------------

ALTER TABLE public.user_profiles
  ADD COLUMN IF NOT EXISTS last_seen_at timestamptz,
  ADD COLUMN IF NOT EXISTS consent_marketing_at timestamptz;

COMMENT ON COLUMN public.user_profiles.last_seen_at IS
  'When this person was last seen in this workspace (the web, later the phone), written at most once an hour. NULL = not seen since the column was added.';
COMMENT ON COLUMN public.user_profiles.consent_marketing_at IS
  'When this person agreed to marketing email from Sellton. NULL = no consent.';

-- 2. The rollup: one row per workspace -------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.backoffice_cs_segment_inputs_v1()
RETURNS TABLE (
  organization_id text,
  name text,
  created_at timestamptz,
  signup_source text,
  mobile_configured boolean,
  onboarding_status text,
  onboarding_completed_at timestamptz,
  activation_paid_at timestamptz,
  has_card_on_file boolean,
  billing_status text,
  trial_started_at timestamptz,
  trial_ends_at timestamptz,
  mobile_trial_ends_at timestamptz,
  mobile_activated_at timestamptz,
  member_count integer,
  active_seats integer,
  terminated_seats integer,
  plays_total integer,
  plays_live integer,
  first_play_launched_at timestamptz,
  last_human_action_at timestamptz,
  last_seen_at timestamptz,
  activity_window_days integer,
  approvals_7d integer,
  approvals_prev_7d integer,
  pending_approvals integer,
  emails_sent_30d integer,
  replies_30d integer,
  meetings_30d integer,
  last_customer_email_at timestamptz,
  last_customer_reply_at timestamptz,
  last_chase_at timestamptz,
  timezone text,
  send_window_start integer,
  send_window_end integer,
  send_days integer[],
  marketing_consent_members integer
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  WITH bounds AS (
    SELECT now() - interval '45 days' AS window_start,
           now() - interval '7 days' AS day7,
           now() - interval '14 days' AS day14,
           now() - interval '30 days' AS day30
  ),
  members AS (
    SELECT uo.organization_id,
           count(DISTINCT uo.user_id)::integer AS member_count,
           max(up.last_seen_at) AS last_seen_at,
           count(DISTINCT uo.user_id) FILTER (WHERE up.consent_marketing_at IS NOT NULL)::integer AS consenting
    FROM public.user_organizations uo
    LEFT JOIN public.user_profiles up
      ON up.user_id = uo.user_id AND up.organization_id = uo.organization_id
    GROUP BY uo.organization_id
  ),
  seats AS (
    SELECT s.organization_id,
           count(*) FILTER (WHERE s.seat_status = 'active')::integer AS active_seats,
           count(*) FILTER (WHERE s.seat_status = 'terminated')::integer AS terminated_seats,
           max(s.mobile_trial_ends_at) AS mobile_trial_ends_at,
           min(s.mobile_activated_at) AS mobile_activated_at
    FROM public.org_seats s
    GROUP BY s.organization_id
  ),
  plays AS (
    SELECT c.organization_id,
           count(*)::integer AS plays_total,
           count(*) FILTER (WHERE c.status::text = 'active')::integer AS plays_live,
           min(coalesce(c.launched_at, c.started_at)) AS first_play_launched_at,
           max(c.created_at) FILTER (WHERE c.created_at >= b.window_start) AS last_play_created_at
    FROM public.campaigns c
    CROSS JOIN bounds b
    WHERE c.status::text <> 'cancelled'
    GROUP BY c.organization_id
  ),
  task_rollup AS (
    SELECT t.organization_id,
           max(t.completed_at) FILTER (WHERE done_by.user_id IS NOT NULL AND t.completed_at >= b.window_start) AS last_approval_at,
           max(t.created_at) FILTER (WHERE made_by.user_id IS NOT NULL AND t.created_at >= b.window_start) AS last_task_created_at,
           count(*) FILTER (WHERE done_by.user_id IS NOT NULL AND t.completed_at >= b.day7)::integer AS approvals_7d,
           count(*) FILTER (WHERE done_by.user_id IS NOT NULL AND t.completed_at >= b.day14 AND t.completed_at < b.day7)::integer AS approvals_prev_7d,
           count(*) FILTER (WHERE t.status::text = 'pending')::integer AS pending_approvals,
           count(*) FILTER (WHERE t.task_type::text = 'meeting' AND t.created_at >= b.day30)::integer AS meetings_30d
    FROM public.tasks t
    CROSS JOIN bounds b
    LEFT JOIN public.user_organizations done_by
      ON done_by.organization_id = t.organization_id AND done_by.user_id = t.completed_by_user_id
    LEFT JOIN public.user_organizations made_by
      ON made_by.organization_id = t.organization_id AND made_by.user_id = t.created_by_user_id
    WHERE t.status::text = 'pending'
       OR t.completed_at >= b.window_start
       OR t.created_at >= b.window_start
    GROUP BY t.organization_id
  ),
  emails AS (
    SELECT e.organization_id,
           count(*) FILTER (WHERE e.sent_at >= b.day30)::integer AS emails_sent_30d,
           count(*) FILTER (WHERE e.replied_at >= b.day30)::integer AS replies_30d
    FROM public.campaign_emails e
    CROSS JOIN bounds b
    WHERE e.sent_at >= b.day30 OR e.replied_at >= b.day30
    GROUP BY e.organization_id
  ),
  files AS (
    SELECT f.organization_id, max(f.uploaded_at) AS last_upload_at
    FROM public.organization_files f
    CROSS JOIN bounds b
    WHERE f.uploaded_at >= b.window_start
      AND lower(btrim(f.uploaded_by)) NOT IN ('', 'api', 'system')
    GROUP BY f.organization_id
  ),
  chases AS (
    SELECT r.organization_id, max(r.sent_at) AS last_chase_at
    FROM public.onboarding_reengagement_sends r
    CROSS JOIN bounds b
    WHERE r.sent_at >= b.day30
    GROUP BY r.organization_id
  ),
  broadcasts AS (
    SELECT s.organization_id, max(s.sent_at) AS last_broadcast_at
    FROM public.email_broadcast_sends s
    CROSS JOIN bounds b
    WHERE s.status = 'sent' AND s.sent_at >= b.day30 AND s.organization_id IS NOT NULL
    GROUP BY s.organization_id
  ),
  cs_emails AS (
    SELECT r.organization_id,
           max(r.executed_at) FILTER (WHERE r.status = 'executed') AS last_executed_at,
           max(CASE
                 WHEN r.outcome->>'replied_at' ~ '^\d{4}-\d{2}-\d{2}([T ]\d{2}:\d{2}(:\d{2}(\.\d{1,6})?)?)?(Z|[+-]\d{2}(:?\d{2})?)?$'
                 THEN (r.outcome->>'replied_at')::timestamptz
               END) AS last_reply_at
    FROM public.cs_recommendations r
    CROSS JOIN bounds b
    WHERE r.kind = 'email' AND r.created_at >= b.day30
    GROUP BY r.organization_id
  )
  SELECT
    o.id,
    o.name,
    o.created_at,
    o.signup_source,
    coalesce(jsonb_typeof(o.mobile) <> 'null', false),
    o.onboarding_status,
    os.onboarding_completed_at,
    o.activation_paid_at,
    coalesce(nullif(bc.card_brand, ''), nullif(bc.card_last4, '')) IS NOT NULL,
    bc.status,
    bc.trial_started_at,
    bc.trial_ends_at,
    se.mobile_trial_ends_at,
    se.mobile_activated_at,
    coalesce(m.member_count, 0),
    coalesce(se.active_seats, 0),
    coalesce(se.terminated_seats, 0),
    coalesce(p.plays_total, 0),
    coalesce(p.plays_live, 0),
    p.first_play_launched_at,
    greatest(tr.last_approval_at, tr.last_task_created_at, p.last_play_created_at, f.last_upload_at),
    m.last_seen_at,
    45,
    coalesce(tr.approvals_7d, 0),
    coalesce(tr.approvals_prev_7d, 0),
    coalesce(tr.pending_approvals, 0),
    coalesce(e.emails_sent_30d, 0),
    coalesce(e.replies_30d, 0),
    coalesce(tr.meetings_30d, 0),
    greatest(ch.last_chase_at, br.last_broadcast_at, ce.last_executed_at),
    ce.last_reply_at,
    ch.last_chase_at,
    os.timezone,
    os.send_window_start::integer,
    os.send_window_end::integer,
    os.send_days::integer[],
    coalesce(m.consenting, 0)
  FROM public.organization o
  LEFT JOIN public.organization_settings os ON os.organization_id = o.id
  LEFT JOIN public.billing_customers bc ON bc.organization_id = o.id
  LEFT JOIN members m ON m.organization_id = o.id
  LEFT JOIN seats se ON se.organization_id = o.id
  LEFT JOIN plays p ON p.organization_id = o.id
  LEFT JOIN task_rollup tr ON tr.organization_id = o.id
  LEFT JOIN emails e ON e.organization_id = o.id
  LEFT JOIN files f ON f.organization_id = o.id
  LEFT JOIN chases ch ON ch.organization_id = o.id
  LEFT JOIN broadcasts br ON br.organization_id = o.id
  LEFT JOIN cs_emails ce ON ce.organization_id = o.id
  WHERE o.deleted = false
  ORDER BY o.id;
$$;

COMMENT ON FUNCTION public.backoffice_cs_segment_inputs_v1() IS
  'Backoffice customer-success agent: one row per organization with deleted = false, the lifecycle classifier''s inputs (onboarding, billing, people, plays, human activity, approvals, outcomes, our own email to the customer, send window, marketing consent). Read-only, service role only.';

-- 3. One workspace's facts -----------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.backoffice_cs_workspace_facts_v1(p_org text)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  WITH b AS (
    SELECT now() AS at,
           now() - interval '45 days' AS window_start,
           now() - interval '7 days' AS day7,
           now() - interval '14 days' AS day14,
           now() - interval '28 days' AS day28,
           now() - interval '30 days' AS day30,
           now() - interval '60 days' AS day60
  ),
  org AS (
    SELECT o.id, o.name, o.tier, o.created_at, o.signup_source, o.onboarding_status, o.onboarding_mode,
           o.activation_paid_at, o.work_access_mode, o.dispatch_suspended
    FROM public.organization o
    WHERE o.id = p_org
  ),
  st AS (
    SELECT s.timezone, s.send_window_start, s.send_window_end, s.send_days
    FROM public.organization_settings s
    WHERE s.organization_id = p_org
  ),
  mem AS (
    SELECT count(DISTINCT uo.user_id)::integer AS total,
           count(DISTINCT uo.user_id) FILTER (
             WHERE lower(btrim(uo.role)) IN ('org:admin', 'org:owner', 'admin', 'owner'))::integer AS admins,
           max(up.last_seen_at) AS last_seen_at,
           count(DISTINCT uo.user_id) FILTER (WHERE up.consent_marketing_at IS NOT NULL)::integer AS marketing_consent
    FROM public.user_organizations uo
    LEFT JOIN public.user_profiles up
      ON up.user_id = uo.user_id AND up.organization_id = uo.organization_id
    WHERE uo.organization_id = p_org
  ),
  seat AS (
    SELECT count(*) FILTER (WHERE s.seat_status = 'active')::integer AS active,
           count(*) FILTER (WHERE s.seat_status = 'active' AND s.is_billable)::integer AS billable,
           count(*) FILTER (WHERE s.seat_status = 'active' AND s.mobile_activated_at IS NULL)::integer AS web,
           count(*) FILTER (WHERE s.seat_status = 'active' AND s.mobile_activated_at IS NOT NULL)::integer AS mobile,
           count(DISTINCT s.clerk_user_id) FILTER (
             WHERE s.seat_status = 'active'
               AND (s.mobile_trial_started_at IS NOT NULL OR s.mobile_activated_at IS NOT NULL))::integer AS phone_users,
           max(s.mobile_trial_ends_at) AS mobile_trial_ends_at
    FROM public.org_seats s
    WHERE s.organization_id = p_org
  ),
  research AS (
    SELECT r.status, r.created_at, r.updated_at, r.fit_type, r.is_supported,
           nullif(r.interview_call_id, '') IS NOT NULL AS has_interview,
           nullif(r.error_message, '') IS NOT NULL AS has_error
    FROM public.onboarding_research r
    WHERE r.organization_id = p_org
  ),
  play AS (
    SELECT c.id, c.name, c.status::text AS status, c.created_at, coalesce(c.launched_at, c.started_at) AS launched_at
    FROM public.campaigns c
    WHERE c.organization_id = p_org
  ),
  play_summary AS (
    SELECT count(*)::integer AS total,
           count(*) FILTER (WHERE status = 'active')::integer AS active,
           count(*) FILTER (WHERE status = 'draft')::integer AS draft,
           count(*) FILTER (WHERE status IN ('completed', 'fully_completed'))::integer AS completed,
           min(launched_at) AS first_launched_at,
           max(launched_at) AS last_launched_at,
           max(created_at) FILTER (WHERE status <> 'cancelled') AS last_created_at,
           count(*) FILTER (WHERE status <> 'cancelled' AND created_at >= (SELECT day7 FROM b))::integer AS created_7d
    FROM play
  ),
  -- One pass over the workspace's tasks, grouped by play (campaign_id NULL is the workspace's own group).
  task_by_play AS (
    SELECT t.campaign_id,
           count(*) FILTER (WHERE done_by.user_id IS NOT NULL AND t.completed_at >= b.day30)::integer AS approvals_30d,
           count(*) FILTER (WHERE done_by.user_id IS NOT NULL AND t.completed_at IS NOT NULL)::integer AS approvals_total,
           max(t.completed_at) FILTER (WHERE done_by.user_id IS NOT NULL) AS last_approval_at,
           count(*) FILTER (WHERE t.status::text = 'pending')::integer AS drafts_waiting,
           count(*) FILTER (WHERE t.task_type::text = 'meeting' AND t.created_at >= b.day30)::integer AS meetings_30d,
           count(*) FILTER (WHERE t.task_type::text = 'meeting')::integer AS meetings_total,
           max(t.created_at) FILTER (WHERE t.task_type::text = 'meeting') AS last_meeting_at,
           max(t.completed_at) FILTER (WHERE done_by.user_id IS NOT NULL AND t.completed_at >= b.window_start) AS last_human_completed_at,
           max(t.created_at) FILTER (WHERE made_by.user_id IS NOT NULL AND t.created_at >= b.window_start) AS last_human_created_at,
           (count(*) FILTER (WHERE done_by.user_id IS NOT NULL AND t.completed_at >= b.day7)
            + count(*) FILTER (WHERE made_by.user_id IS NOT NULL AND t.created_at >= b.day7))::integer AS human_actions_7d
    FROM public.tasks t
    CROSS JOIN b
    LEFT JOIN public.user_organizations done_by
      ON done_by.organization_id = t.organization_id AND done_by.user_id = t.completed_by_user_id
    LEFT JOIN public.user_organizations made_by
      ON made_by.organization_id = t.organization_id AND made_by.user_id = t.created_by_user_id
    WHERE t.organization_id = p_org
    GROUP BY t.campaign_id
  ),
  task_total AS (
    SELECT coalesce(sum(approvals_30d), 0)::integer AS approvals_30d,
           coalesce(sum(approvals_total), 0)::integer AS approvals_total,
           max(last_approval_at) AS last_approval_at,
           coalesce(sum(drafts_waiting), 0)::integer AS drafts_waiting,
           coalesce(sum(meetings_30d), 0)::integer AS meetings_30d,
           coalesce(sum(meetings_total), 0)::integer AS meetings_total,
           max(last_meeting_at) AS last_meeting_at,
           greatest(max(last_human_completed_at), max(last_human_created_at)) AS last_human_task_at,
           coalesce(sum(human_actions_7d), 0)::integer AS human_actions_7d
    FROM task_by_play
  ),
  -- One pass over the workspace's campaign emails, grouped by play. Counts and times only.
  email_by_play AS (
    SELECT e.campaign_id,
           count(*) FILTER (WHERE e.sent_at >= b.day30)::integer AS sent_30d,
           count(*) FILTER (WHERE e.replied_at >= b.day30)::integer AS replies_30d,
           count(*) FILTER (WHERE e.replied_at >= b.day30
                              AND e.classification->>'intent' = 'positive_intent')::integer AS positive_30d,
           max(e.replied_at) AS last_reply_at
    FROM public.campaign_emails e
    CROSS JOIN b
    WHERE e.organization_id = p_org
      AND (e.sent_at >= b.day30 OR e.replied_at IS NOT NULL)
    GROUP BY e.campaign_id
  ),
  email_total AS (
    SELECT coalesce(sum(sent_30d), 0)::integer AS sent_30d,
           coalesce(sum(replies_30d), 0)::integer AS replies_30d,
           coalesce(sum(positive_30d), 0)::integer AS positive_30d,
           max(last_reply_at) AS last_reply_at
    FROM email_by_play
  ),
  linkedin_sent AS (
    SELECT count(*)::integer AS sent_30d
    FROM public.linkedin_action_log l
    CROSS JOIN b
    WHERE l.organization_id = p_org
      AND l.created_at >= b.day30
      AND l.success
      AND l.action_type IN ('invitation', 'message')
  ),
  files AS (
    SELECT max(f.uploaded_at) FILTER (WHERE f.uploaded_at >= b.window_start) AS last_upload_at,
           count(*) FILTER (WHERE f.uploaded_at >= b.day7)::integer AS uploads_7d
    FROM public.organization_files f
    CROSS JOIN b
    WHERE f.organization_id = p_org
      AND f.uploaded_at >= b.window_start
      AND lower(btrim(f.uploaded_by)) NOT IN ('', 'api', 'system')
  ),
  human AS (
    SELECT greatest(tt.last_human_task_at,
                    CASE WHEN ps.last_created_at >= b.window_start THEN ps.last_created_at END,
                    f.last_upload_at) AS last_at,
           tt.human_actions_7d + ps.created_7d + f.uploads_7d AS actions_7d
    FROM task_total tt, play_summary ps, files f, b
  ),
  bc AS (
    SELECT c.status, c.card_brand, c.card_last4, c.billing_started_at, c.trial_started_at, c.trial_ends_at,
           c.monthly_spend_limit
    FROM public.billing_customers c
    WHERE c.organization_id = p_org
  ),
  credit AS (
    SELECT coalesce(sum(c.remaining_usd) FILTER (WHERE c.expires_at IS NULL OR c.expires_at > b.at), 0) AS remaining_usd,
           count(*) FILTER (WHERE c.kind = 'trial') AS trial_rows,
           sum(c.amount_usd) FILTER (WHERE c.kind = 'trial') AS trial_usd,
           coalesce(sum(c.remaining_usd) FILTER (WHERE c.kind = 'trial' AND (c.expires_at IS NULL OR c.expires_at > b.at)), 0) AS trial_remaining_usd
    FROM public.billing_credits c
    CROSS JOIN b
    WHERE c.organization_id = p_org
  ),
  spend AS (
    SELECT coalesce(sum(u.sellton_cost) FILTER (WHERE u.created_at >= b.day7), 0) AS usage_7d,
           coalesce(sum(u.sellton_cost) FILTER (WHERE u.created_at >= b.day14 AND u.created_at < b.day7), 0) AS usage_prev_7d,
           coalesce(sum(u.sellton_cost), 0) AS usage_28d
    FROM public.usage u
    CROSS JOIN b
    WHERE u.organization_id = p_org
      AND u.created_at >= b.day28
  ),
  invoice AS (
    SELECT max(i.created_at) FILTER (WHERE i.status <> 'draft') AS last_invoice_at,
           coalesce(sum(i.total) FILTER (WHERE i.status IN ('open', 'sent', 'failed')), 0) AS open_usd,
           coalesce(bool_or(i.status = 'paid' AND i.paid_at >= b.day60), false) AS paid_60d
    FROM public.billing_invoices i
    CROSS JOIN b
    WHERE i.organization_id = p_org
  ),
  discount AS (
    SELECT max(dc.discount_value) AS percent
    FROM public.discount_code_redemptions r
    JOIN public.discount_codes dc ON dc.code = r.code
    WHERE r.organization_id = p_org
      AND dc.applies_to = 'seats'
      AND dc.discount_type = 'percentage'
      AND dc.is_active
  ),
  req AS (
    SELECT count(*) FILTER (WHERE r.status IN ('new', 'in_progress'))::integer AS open,
           coalesce(bool_or(r.type = 'leave' AND r.status IN ('new', 'in_progress')), false) AS leave_open,
           (array_agg(r.type ORDER BY r.created_at DESC, r.id DESC))[1] AS last_type,
           max(r.created_at) AS last_at
    FROM public.customer_requests r
    WHERE r.organization_id = p_org
  ),
  linkedin AS (
    SELECT count(*) FILTER (WHERE a.status = 'active')::integer AS connected,
           count(*) FILTER (WHERE a.status IN ('disconnected', 'credentials_expired', 'restricted', 'error'))::integer AS disconnected,
           max(coalesce(a.disconnected_at, a.last_status_change_at))
             FILTER (WHERE a.status IN ('disconnected', 'credentials_expired', 'restricted', 'error')) AS last_disconnected_at
    FROM public.linkedin_accounts a
    WHERE a.organization_id = p_org
      AND a.provider = 'LINKEDIN'
  ),
  notes AS (
    SELECT count(*)::integer AS total,
           count(*) FILTER (WHERE n.created_by = 'agent')::integer AS by_agent,
           max(n.created_at) AS last_at
    FROM public.backoffice_org_notes n
    WHERE n.organization_id = p_org
      AND n.archived_at IS NULL
  ),
  support AS (
    SELECT count(*) FILTER (WHERE s.created_at >= b.day30)::integer AS sessions_30d,
           coalesce(bool_or(s.status = 'active' AND s.revoked_at IS NULL AND s.expires_at > b.at), false) AS active,
           max(s.created_at) AS last_at
    FROM public.support_workspace_sessions s
    CROSS JOIN b
    WHERE s.organization_id = p_org
  ),
  -- Our own email to the customer, last 30 days (the same sources and window as the rollup).
  our_email AS (
    SELECT greatest(
             (SELECT max(r.sent_at) FROM public.onboarding_reengagement_sends r
               WHERE r.organization_id = p_org AND r.sent_at >= b.day30),
             (SELECT max(s.sent_at) FROM public.email_broadcast_sends s
               WHERE s.organization_id = p_org AND s.status = 'sent' AND s.sent_at >= b.day30),
             (SELECT max(r.executed_at) FROM public.cs_recommendations r
               WHERE r.organization_id = p_org AND r.kind = 'email' AND r.status = 'executed' AND r.created_at >= b.day30)
           ) AS last_email_at,
           (SELECT max(CASE
                         WHEN r.outcome->>'replied_at' ~ '^\d{4}-\d{2}-\d{2}([T ]\d{2}:\d{2}(:\d{2}(\.\d{1,6})?)?)?(Z|[+-]\d{2}(:?\d{2})?)?$'
                         THEN (r.outcome->>'replied_at')::timestamptz
                       END)
              FROM public.cs_recommendations r
             WHERE r.organization_id = p_org AND r.kind = 'email' AND r.created_at >= b.day30) AS last_reply_at
    FROM b
  ),
  caps AS (
    SELECT e.last_email_at,
           (e.last_reply_at IS NOT NULL AND (e.last_email_at IS NULL OR e.last_reply_at >= e.last_email_at)) AS replied_since
    FROM our_email e
  ),
  -- The workspace's local time: organization_settings.timezone when this server knows the zone, else UTC.
  local_clock AS (
    SELECT st.send_window_start, st.send_window_end, st.send_days,
           (b.at AT TIME ZONE coalesce(
              (SELECT z.name FROM pg_catalog.pg_timezone_names z WHERE z.name = st.timezone LIMIT 1), 'UTC')) AS local_ts
    FROM st, b
  ),
  quiet AS (
    SELECT coalesce(bool_or(
             lc.send_window_start IS NOT NULL
             AND (NOT (extract(dow FROM lc.local_ts)::smallint = ANY (lc.send_days))
                  OR (extract(hour FROM lc.local_ts) * 60 + extract(minute FROM lc.local_ts)) < lc.send_window_start
                  OR (extract(hour FROM lc.local_ts) * 60 + extract(minute FROM lc.local_ts)) >= lc.send_window_end)), false) AS in_quiet_hours
    FROM local_clock lc
  ),
  recs AS (
    SELECT count(*) FILTER (WHERE r.status = 'proposed')::integer AS proposed,
           (array_agg(r.kind ORDER BY r.created_at DESC, r.id DESC))[1] AS last_kind,
           max(r.created_at) AS last_at
    FROM public.cs_recommendations r
    WHERE r.organization_id = p_org
  ),
  items AS (
    SELECT coalesce(jsonb_agg(jsonb_build_object(
             'id', x.id::text,
             'name', x.name,
             'status', x.status,
             'created_at', x.created_at,
             'launched_at', x.launched_at,
             'approvals_30d', coalesce(x.approvals_30d, 0),
             'sent_30d', coalesce(x.sent_30d, 0),
             'replies_30d', coalesce(x.replies_30d, 0),
             'meetings_30d', coalesce(x.meetings_30d, 0),
             'drafts_waiting', coalesce(x.drafts_waiting, 0)
           ) ORDER BY x.created_at DESC NULLS LAST, x.id DESC), '[]'::jsonb) AS list
    FROM (
      SELECT p.id, p.name, p.status, p.created_at, p.launched_at,
             tp.approvals_30d, tp.meetings_30d, tp.drafts_waiting, ep.sent_30d, ep.replies_30d
      FROM play p
      LEFT JOIN task_by_play tp ON tp.campaign_id = p.id
      LEFT JOIN email_by_play ep ON ep.campaign_id = p.id
      ORDER BY p.created_at DESC NULLS LAST, p.id DESC
      LIMIT 20
    ) x
  )
  SELECT jsonb_build_object(
    'generated_at', b.at,
    'organization', jsonb_build_object(
      'id', o.id,
      'name', o.name,
      'tier', o.tier,
      'created_at', o.created_at,
      'signup_source', CASE WHEN o.signup_source = 'mobile' THEN 'mobile' ELSE 'web' END,
      'onboarding_status', o.onboarding_status,
      'onboarding_mode', o.onboarding_mode,
      'activation_paid_at', o.activation_paid_at,
      'work_access_mode', o.work_access_mode,
      'dispatch_suspended', coalesce(o.dispatch_suspended, false),
      'timezone', (SELECT st.timezone FROM st),
      'last_seen_at', mem.last_seen_at
    ),
    'segment', NULL::text,
    'health_score', NULL::numeric,
    'members', jsonb_build_object(
      'total', mem.total,
      'admins', mem.admins,
      'web_users', 0,
      'phone_users', seat.phone_users,
      'last_web_login_at', NULL::timestamptz,
      'marketing_consent', mem.marketing_consent
    ),
    'seats', jsonb_build_object(
      'active', seat.active,
      'billable', seat.billable,
      'web', seat.web,
      'mobile', seat.mobile
    ),
    'research', jsonb_build_object(
      'status', r.status,
      'started_at', r.created_at,
      'updated_at', r.updated_at,
      'days_in_status', CASE WHEN r.updated_at IS NOT NULL
                             THEN greatest(0, floor(extract(epoch FROM (b.at - r.updated_at)) / 86400))::integer END,
      'fit_type', r.fit_type,
      'is_supported', r.is_supported,
      'has_interview', coalesce(r.has_interview, false),
      'error', coalesce(r.has_error, false)
    ),
    'plays', jsonb_build_object(
      'total', ps.total,
      'active', ps.active,
      'draft', ps.draft,
      'approved_not_launched', 0,
      'completed', ps.completed,
      'first_launched_at', ps.first_launched_at,
      'last_launched_at', ps.last_launched_at,
      'items', items.list
    ),
    'outcomes', jsonb_build_object(
      'window_days', 30,
      'approvals', tt.approvals_30d,
      'approvals_total', tt.approvals_total,
      'drafts_waiting', tt.drafts_waiting,
      'emails_sent', et.sent_30d,
      'linkedin_sent', ls.sent_30d,
      'replies', et.replies_30d,
      'positive_replies', et.positive_30d,
      'meetings', tt.meetings_30d,
      'meetings_total', tt.meetings_total,
      'last_approval_at', tt.last_approval_at,
      'last_reply_at', et.last_reply_at,
      'last_meeting_at', tt.last_meeting_at
    ),
    'activity', jsonb_build_object(
      'last_human_action_at', human.last_at,
      'days_since_human_action', CASE WHEN human.last_at IS NOT NULL
                                      THEN greatest(0, floor(extract(epoch FROM (b.at - human.last_at)) / 86400))::integer END,
      'human_actions_7d', human.actions_7d
    ),
    'billing', jsonb_build_object(
      'status', bc.status,
      'card_on_file', coalesce(nullif(bc.card_brand, ''), nullif(bc.card_last4, '')) IS NOT NULL,
      'billing_started_at', bc.billing_started_at,
      'paying', invoice.paid_60d
                OR (bc.billing_started_at IS NOT NULL
                    AND coalesce(nullif(bc.card_brand, ''), nullif(bc.card_last4, '')) IS NOT NULL),
      'trial_active', coalesce(
                        CASE WHEN o.signup_source = 'mobile' THEN seat.mobile_trial_ends_at ELSE bc.trial_ends_at END > b.at,
                        false),
      'trial_ends_at', CASE WHEN o.signup_source = 'mobile' THEN seat.mobile_trial_ends_at ELSE bc.trial_ends_at END,
      'trial_credit_usd', CASE WHEN credit.trial_rows > 0 THEN round(credit.trial_usd, 2) END,
      'trial_credit_remaining_usd', CASE WHEN credit.trial_rows > 0 THEN round(credit.trial_remaining_usd, 2) END,
      'credit_remaining_usd', round(credit.remaining_usd, 2),
      'monthly_spend_limit_usd', bc.monthly_spend_limit,
      'usage_7d_usd', round(spend.usage_7d, 2),
      'usage_prev_7d_usd', round(spend.usage_prev_7d, 2),
      'usage_28d_usd', round(spend.usage_28d, 2),
      'last_invoice_at', invoice.last_invoice_at,
      'open_invoice_usd', round(invoice.open_usd, 2),
      'seat_discount_percent', discount.percent
    ),
    'requests', jsonb_build_object(
      'open', req.open,
      'leave_open', req.leave_open,
      'last_type', req.last_type,
      'last_at', req.last_at
    ),
    'mailboxes', jsonb_build_object(
      'email_connected', 0,
      'email_disconnected', 0,
      'linkedin_connected', linkedin.connected,
      'linkedin_disconnected', linkedin.disconnected,
      'last_disconnected_at', linkedin.last_disconnected_at
    ),
    'notes', jsonb_build_object(
      'count', notes.total,
      'agent_count', notes.by_agent,
      'last_at', notes.last_at
    ),
    'support', jsonb_build_object(
      'sessions_30d', support.sessions_30d,
      'active_session', support.active,
      'last_session_at', support.last_at
    ),
    'caps', jsonb_build_object(
      'last_customer_email_at', caps.last_email_at,
      'customer_replied_since_last_email', caps.replied_since,
      'can_email', caps.last_email_at IS NULL OR caps.last_email_at <= b.at - interval '7 days' OR caps.replied_since,
      'next_email_at', CASE WHEN caps.last_email_at > b.at - interval '7 days' AND NOT caps.replied_since
                            THEN caps.last_email_at + interval '7 days' END,
      'in_quiet_hours', quiet.in_quiet_hours
    ),
    'recommendations', jsonb_build_object(
      'proposed', recs.proposed,
      'last_kind', recs.last_kind,
      'last_at', recs.last_at
    )
  )
  FROM org o
  CROSS JOIN b
  CROSS JOIN mem
  CROSS JOIN seat
  LEFT JOIN research r ON true
  CROSS JOIN play_summary ps
  CROSS JOIN items
  CROSS JOIN task_total tt
  CROSS JOIN email_total et
  CROSS JOIN linkedin_sent ls
  CROSS JOIN human
  LEFT JOIN bc ON true
  CROSS JOIN credit
  CROSS JOIN spend
  CROSS JOIN invoice
  CROSS JOIN discount
  CROSS JOIN req
  CROSS JOIN linkedin
  CROSS JOIN notes
  CROSS JOIN support
  CROSS JOIN caps
  CROSS JOIN quiet
  CROSS JOIN recs;
$$;

COMMENT ON FUNCTION public.backoffice_cs_workspace_facts_v1(text) IS
  'Backoffice customer-success agent: one workspace''s facts as one jsonb object (organization, members, seats, research, plays with at most 20 items newest first, outcomes, activity, billing, requests, mailboxes, notes, support, caps, recommendations). Aggregates and the workspace''s own data only: no prospect name, prospect email or reply body. segment and health_score are null (the backoffice computes them). NULL for an unknown organization. Read-only, service role only.';

-- Access: the service role only ------------------------------------------------------------------
-- Functions are executable by PUBLIC by default, and Supabase grants new functions to anon and authenticated.

REVOKE ALL ON FUNCTION public.backoffice_cs_segment_inputs_v1() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.backoffice_cs_workspace_facts_v1(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.backoffice_cs_segment_inputs_v1() TO service_role;
GRANT EXECUTE ON FUNCTION public.backoffice_cs_workspace_facts_v1(text) TO service_role;

-- Fail the file if a browser key can still execute either function.
DO $$
DECLARE f text;
BEGIN
  FOREACH f IN ARRAY ARRAY['public.backoffice_cs_segment_inputs_v1()', 'public.backoffice_cs_workspace_facts_v1(text)'] LOOP
    IF has_function_privilege('anon', f, 'EXECUTE') OR has_function_privilege('authenticated', f, 'EXECUTE') THEN
      RAISE EXCEPTION '423: anon or authenticated can still execute %', f;
    END IF;
    IF NOT has_function_privilege('service_role', f, 'EXECUTE') THEN
      RAISE EXCEPTION '423: service_role cannot execute %', f;
    END IF;
  END LOOP;
END $$;

-- Verify (read-only):
-- select column_name, data_type from information_schema.columns
--  where table_schema = 'public' and table_name = 'user_profiles'
--    and column_name in ('last_seen_at', 'consent_marketing_at') order by 1;
--   -> two rows, timestamp with time zone
-- select has_function_privilege('anon', 'public.backoffice_cs_segment_inputs_v1()', 'EXECUTE'),          -- false
--        has_function_privilege('service_role', 'public.backoffice_cs_workspace_facts_v1(text)', 'EXECUTE'); -- true
-- select count(*) = (select count(*) from public.organization where deleted = false)
--   from public.backoffice_cs_segment_inputs_v1();                                                       -- true
-- select jsonb_object_keys(public.backoffice_cs_workspace_facts_v1('<org>'));                             -- 17 keys
