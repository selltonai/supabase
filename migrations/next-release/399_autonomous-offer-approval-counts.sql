-- ============================================================
-- Migration: autonomous-offer-approval-counts (stage: next-release/399; renumber at promotion)
-- Date:      2026-10-15
-- Purpose:   KAN-322 FR-B8 (D11, D58): the Autonomous offer. After 25 approvals of one type in a play, approved as-is
--            or edited by a person (never by Autonomous), Sellton offers to approve that type on its own.
--              1. campaign_human_approval_counts_v1 - human approvals per play and type, in one grouped read.
--              2. user_profiles.ui_seen             - per user and workspace, which offers the person has seen
--                 (never the campaign's own row: the wizard's autosave guards it).
-- Projects:  selltonai-database/supabase (owner); reader and writer: selltonai /api/autonomous/offers (FR-B8b, behind
--            NEXT_PUBLIC_REFRESH_SHELL_ENABLED).
-- Contract:  One read-only function and one additive column (jsonb, NOT NULL, default '{}'). No constraint, RLS,
--            trigger, cron or queue change. Safe to drop (the offer card shows nothing).
-- Depends:   tasks (task_type, status, campaign_id, completed_by_user_id, metadata), user_profiles.
--
-- What counts as a person's approval (verified on origin/stage 2026-10-15, BFF and Modal):
--   company          task_type company_verification, status completed, metadata.verification_result 'approved',
--                    metadata.verified_by a user (Autonomous writes 'api': Modal task_service, the BFF self-PATCH).
--   email            task_type review_draft, channel email (or none), status completed or scheduled, and a user in
--                    metadata.accepted_by, or metadata.approvedBy (bulk approval, which can fall back to 'api' in
--                    accepted_by when its session expires), or, with no accepted_by at all (the legacy PATCH),
--                    completed_by_user_id. Autonomous writes accepted_by 'api' and completed_by_user_id 'api'.
--                    The kind is Modal's email_type (frontend_task_service.py), read as Modal reads it:
--                    the first non-empty of email_type, emailType, type, reply_type, replyType, trimmed and lower-cased.
--   LinkedIn         task_type review_draft, channel linkedin, status completed or scheduled, and a user in
--                    metadata.last_dispatch.approved_by_user_id (sent now) or metadata.li_dispatch_approved_by
--                    (scheduled, kept when the dispatcher completes it). Autonomous writes neither to a user
--                    (li_dispatch_approved_by 'autopilot'). metadata.autopilot is NOT used: a task Autonomous scheduled
--                    and the dispatcher returned to pending keeps it after a person approves it.
--                    invitation: linkedin_action_type 'invitation'; any other LinkedIn draft is a message.
--   Declines are cancelled (or 'declined', which the enum lacks), so they never count. LinkedIn replies
--   (review_reply) are not counted: their switch never sends.
--
-- Performance: one pass over the workspace's completed and scheduled tasks of two types (idx_tasks_org_status_priority_
--   created leads with organization_id, status; one play uses idx_tasks_campaign_id), grouped into at most six rows per
--   play. Measured on a disposable Postgres 15 with 400,000 tasks in one workspace (see the FR-B8a report).
--   STABLE, SECURITY DEFINER (service_role only; tasks carry other people's drafts).
--
-- Rollback: DROP FUNCTION IF EXISTS public.campaign_human_approval_counts_v1(text, uuid);
--           ALTER TABLE public.user_profiles DROP COLUMN IF EXISTS ui_seen;
-- ============================================================

ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS ui_seen jsonb NOT NULL DEFAULT '{}'::jsonb;

COMMENT ON COLUMN public.user_profiles.ui_seen IS
  'KAN-322 FR-B8: what this person has seen in this workspace, by feature (autonomous_offer: {"<campaign_id>:<type>": '
  '"<seen at>"}). Written by the BFF only.';

CREATE OR REPLACE FUNCTION public.campaign_human_approval_counts_v1(p_organization_id text, p_campaign_id uuid DEFAULT NULL)
RETURNS TABLE (campaign_id uuid, approval_type text, approvals bigint)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH candidate AS (
    SELECT
      t.campaign_id,
      t.task_type::text AS task_type,
      t.status::text AS status,
      nullif(t.completed_by_user_id, '') AS completed_by,
      t.metadata AS m,
      lower(btrim(coalesce(nullif(t.metadata->>'email_type', ''), nullif(t.metadata->>'emailType', ''), nullif(t.metadata->>'type', ''),
                           nullif(t.metadata->>'reply_type', ''), nullif(t.metadata->>'replyType', ''), ''))) AS email_kind
    FROM public.tasks t
    WHERE t.organization_id = p_organization_id
      AND t.campaign_id IS NOT NULL
      AND (p_campaign_id IS NULL OR t.campaign_id = p_campaign_id)
      AND t.task_type::text IN ('company_verification', 'review_draft')
      AND t.status::text IN ('completed', 'scheduled')
  ),
  typed AS (
    SELECT
      c.campaign_id,
      CASE
        WHEN c.task_type = 'company_verification' THEN
          CASE WHEN c.status = 'completed'
                AND c.m->>'verification_result' = 'approved'
                AND coalesce(nullif(c.m->>'verified_by', ''), 'api') <> 'api'
               THEN 'company' END
        WHEN coalesce(c.m->>'channel', 'email') = 'linkedin' THEN
          CASE WHEN coalesce(nullif(c.m->'last_dispatch'->>'approved_by_user_id', ''), 'autopilot') <> 'autopilot'
                 OR coalesce(nullif(c.m->>'li_dispatch_approved_by', ''), 'autopilot') <> 'autopilot'
               THEN CASE WHEN c.m->>'linkedin_action_type' = 'invitation' THEN 'linkedin_invite' ELSE 'linkedin_message' END
          END
        ELSE
          CASE WHEN coalesce(nullif(c.m->>'accepted_by', ''), 'api') <> 'api'
                 OR coalesce(nullif(c.m->>'approvedBy', ''), 'api') <> 'api'
                 OR (c.m->>'accepted_by' IS NULL AND coalesce(c.completed_by, 'api') <> 'api')
               THEN CASE
                 WHEN c.email_kind IN ('initial', 'new_email') THEN 'initial_email'
                 WHEN c.email_kind IN ('follow_up', 'followup', 'engagement', 'slot_reminder_1', 'slot_reminder_2',
                                       'case_study_followup_1', 'case_study_followup_2', 'positive_follow_up_1',
                                       'positive_follow_up_2') THEN 'followup_email'
                 WHEN c.email_kind IN ('reply', 'meeting_response', 'inquiry_response', 'information_response',
                                       'neutral_follow_up', 'not_interested_response', 'general_response', 'timeslots',
                                       'booking_confirmation') THEN 'reply_email'
               END
          END
      END AS approval_type
    FROM candidate c
  )
  SELECT typed.campaign_id, typed.approval_type, count(*)::bigint AS approvals
  FROM typed
  WHERE typed.approval_type IS NOT NULL
  GROUP BY typed.campaign_id, typed.approval_type;
$$;

COMMENT ON FUNCTION public.campaign_human_approval_counts_v1(text, uuid) IS
  'KAN-322 FR-B8 (D11): per play and type (company, initial_email, followup_email, reply_email, linkedin_invite, '
  'linkedin_message), the tasks a person approved, as-is or edited; never those Autonomous approved. One play with '
  'p_campaign_id, else every play of the workspace.';

REVOKE ALL ON FUNCTION public.campaign_human_approval_counts_v1(text, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.campaign_human_approval_counts_v1(text, uuid) TO service_role;

-- Verify (read-only):
--   SELECT * FROM public.campaign_human_approval_counts_v1('<org_id>') ORDER BY approvals DESC;
--   SELECT column_name, data_type, is_nullable, column_default FROM information_schema.columns
--    WHERE table_schema = 'public' AND table_name = 'user_profiles' AND column_name = 'ui_seen';
--   -- Only service_role may call it (false, false, true):
--   SELECT has_function_privilege('anon', 'public.campaign_human_approval_counts_v1(text,uuid)', 'EXECUTE'),
--          has_function_privilege('authenticated', 'public.campaign_human_approval_counts_v1(text,uuid)', 'EXECUTE'),
--          has_function_privilege('service_role', 'public.campaign_human_approval_counts_v1(text,uuid)', 'EXECUTE');
