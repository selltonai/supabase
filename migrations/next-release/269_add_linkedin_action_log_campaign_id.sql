-- ============================================================
--  Migration: 256_add_linkedin_action_log_campaign_id
--  Date:      2026-05-06
--  V3 P0-J — campaign attribution on linkedin_action_log.
--
--  Problem
--  -------
--  The dashboard-counter endpoint /api/campaigns/linkedin-stats and
--  any future per-campaign analytics need to count invites / messages
--  by campaign. linkedin_action_log was originally designed Phase-2
--  for rate-limiting (account-keyed) — campaign_id wasn't in scope.
--  Adding it now gives us:
--
--    1. /api/campaigns/linkedin-stats works without multi-table joins.
--    2. Per-campaign acceptance / reply attribution stays accurate
--       even when the same account runs multiple campaigns concurrently.
--    3. Consistent with linkedin_messages and campaign_contacts which
--       already carry campaign_id (or its journey-derived parent).
--
--  Backfill
--  --------
--  Existing rows get campaign_id from a join through
--  campaign_sequence_actions → campaign_contacts.campaign_id, when the
--  action_log row's metadata has a sequence_action_id reference.
--  Rows from manual/ad-hoc tasks remain NULL (no campaign context).
--  The backfill is best-effort: rows that can't be matched stay NULL,
--  and the stats query already filters those out.
--
--  Idempotent: ADD COLUMN IF NOT EXISTS, CREATE INDEX IF NOT EXISTS.
-- ============================================================

ALTER TABLE public.linkedin_action_log
  ADD COLUMN IF NOT EXISTS campaign_id UUID;

COMMENT ON COLUMN public.linkedin_action_log.campaign_id IS
  'V3 P0-J — campaign attribution. NULL for manual/ad-hoc actions outside a campaign. Set at write time by linkedin-task-dispatch when the task carries a campaign_id (which it does for sequence-driven sends).';

-- Index for the stats aggregator (organization_id + campaign_id +
-- success). Composite WHERE-success-true matches the linkedin-stats
-- endpoint's query shape.
CREATE INDEX IF NOT EXISTS idx_linkedin_action_log_org_campaign
  ON public.linkedin_action_log(organization_id, campaign_id, action_type)
  WHERE success = TRUE AND campaign_id IS NOT NULL;

-- Best-effort backfill from existing sequence-driven rows. Joins
-- through tasks + campaign_sequence_actions to find the campaign for
-- rows whose request_payload.task_id matches a known sequence task.
-- Skip if you don't have prior data — the WHERE NULL clause makes
-- this a no-op on a fresh table.
UPDATE public.linkedin_action_log AS lal
SET campaign_id = cc.campaign_id
FROM public.tasks AS t
JOIN public.campaign_sequence_actions AS csa ON csa.review_task_id = t.id
JOIN public.campaign_contacts AS cc ON cc.id = csa.campaign_contact_id
WHERE lal.campaign_id IS NULL
  AND (lal.request_payload->>'task_id')::uuid = t.id;

NOTIFY pgrst, 'reload schema';
