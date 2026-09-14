-- 2026-09-14: move the active MyVisits campaign from blagoja@sellton.ai to the
-- customer admin myoung@catanco.com, with MyVisits email dispatch paused around
-- the gmail-api mailbox-owner migration.
--
-- Background: email sends for a campaign resolve their sender from campaigns.user_id
-- (selltonai src/lib/email-task-sender.ts resolveEmailTaskSender -> review-email
-- route sends with tenantuserid = campaign owner). The gmail-api migration
-- migrations/release_1.0.4/01-assign-mailbox-owners-myvisits-chaviation.js makes
-- myoung the owner of all 54 MyVisits mailboxes, including the 11 blagoja owned,
-- so the campaign owner has to move with them.
-- campaigns.user_id also drives campaign notifications (Modal notification_integration),
-- the sender profile used in drafting (email_context_builder_service) and team metrics.
--
-- Why the pause: while the campaign owner and the mailbox owners disagree, a
-- scheduled send whose owner cannot access its mailbox is CANCELLED without retry
-- (gmail-api emailScheduler isNonRetryableSenderConfigurationError). The gmail-api
-- dispatch guard reads organization.dispatch_suspended at send time and defers
-- blocked sends by 15 minutes instead. The BFF guard lets work_access_mode=force_allow
-- win over this flag, so drafting and approvals keep working; only sending waits.
-- Modal billing only clears spend_limit_reached / card_required, never backoffice_manual.
--
-- Operator-run (not in deploy-manifest.txt). Order:
--   0) preview  1) pause  2) move campaign  -> run the gmail-api migration ->  3) resume

-- 0) preview — expect one active campaign owned by user_3GB6YKt8YZCaNu0QWqbuC50dtct,
--    myoung present as a MyVisits member, and dispatch not suspended.
SELECT id, name, status, user_id, organization_id, updated_at
FROM campaigns
WHERE id = '8e4eb33d-0fae-439b-823f-d5354cb8564d';

SELECT uo.user_id, uo.role, u.email
FROM user_organizations uo
JOIN "user" u ON u.id = uo.user_id
WHERE uo.organization_id = 'org_33rpyiDYRk4cfqGLqE0Olc27ptl'
  AND uo.user_id = 'user_39RB7n4XAbFpCbwdVEjo1vazCOg';

SELECT id, dispatch_suspended, dispatch_suspended_reason, dispatch_suspended_at, work_access_mode
FROM organization
WHERE id = 'org_33rpyiDYRk4cfqGLqE0Olc27ptl';

SELECT task_type, status, assigned_to_user_id, count(*)
FROM tasks
WHERE campaign_id = '8e4eb33d-0fae-439b-823f-d5354cb8564d'
  AND status NOT IN ('completed', 'cancelled')
GROUP BY 1, 2, 3;

-- 1) pause MyVisits email dispatch. Refuses if the org is already suspended for
--    another reason, so step 3 never clears a billing suspension.
BEGIN;
DO $$
DECLARE
  current_reason text;
  is_suspended boolean;
BEGIN
  SELECT dispatch_suspended, dispatch_suspended_reason INTO is_suspended, current_reason
  FROM organization WHERE id = 'org_33rpyiDYRk4cfqGLqE0Olc27ptl';

  IF is_suspended IS TRUE AND current_reason IS DISTINCT FROM 'backoffice_manual' THEN
    RAISE EXCEPTION 'MyVisits dispatch is already suspended (reason=%); resolve that first', current_reason;
  END IF;

  UPDATE organization
  SET dispatch_suspended = true,
      dispatch_suspended_reason = 'backoffice_manual',
      dispatch_suspended_at = COALESCE(dispatch_suspended_at, now())
  WHERE id = 'org_33rpyiDYRk4cfqGLqE0Olc27ptl';
END $$;
COMMIT;

-- 2) move the campaign — idempotent, fails loud on any unexpected state.
BEGIN;
DO $$
DECLARE
  moved integer;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM user_organizations
    WHERE organization_id = 'org_33rpyiDYRk4cfqGLqE0Olc27ptl'
      AND user_id = 'user_39RB7n4XAbFpCbwdVEjo1vazCOg'
  ) THEN
    RAISE EXCEPTION 'myoung (user_39RB7n4XAbFpCbwdVEjo1vazCOg) is not a MyVisits member';
  END IF;

  IF EXISTS (
    SELECT 1 FROM campaigns
    WHERE id = '8e4eb33d-0fae-439b-823f-d5354cb8564d'
      AND organization_id = 'org_33rpyiDYRk4cfqGLqE0Olc27ptl'
      AND user_id = 'user_39RB7n4XAbFpCbwdVEjo1vazCOg'
  ) THEN
    RAISE NOTICE 'campaign already owned by myoung; nothing to do';
    RETURN;
  END IF;

  UPDATE campaigns
  SET user_id = 'user_39RB7n4XAbFpCbwdVEjo1vazCOg'
  WHERE id = '8e4eb33d-0fae-439b-823f-d5354cb8564d'
    AND organization_id = 'org_33rpyiDYRk4cfqGLqE0Olc27ptl'
    AND user_id = 'user_3GB6YKt8YZCaNu0QWqbuC50dtct';

  GET DIAGNOSTICS moved = ROW_COUNT;
  IF moved <> 1 THEN
    RAISE EXCEPTION 'expected to move 1 campaign from blagoja to myoung, moved %', moved;
  END IF;
END $$;
COMMIT;

-- >>> Now apply the gmail-api migration (see its runbook), then come back for step 3.

-- 3) resume MyVisits email dispatch — only clears the pause set in step 1.
UPDATE organization
SET dispatch_suspended = false,
    dispatch_suspended_reason = NULL,
    dispatch_suspended_at = NULL
WHERE id = 'org_33rpyiDYRk4cfqGLqE0Olc27ptl'
  AND dispatch_suspended = true
  AND dispatch_suspended_reason = 'backoffice_manual';

-- OPTIONAL — review assignment is separate from the sender. Only run this if myoung
-- (not blagoja) should also review the open drafts.
-- UPDATE tasks
-- SET assigned_to_user_id = 'user_39RB7n4XAbFpCbwdVEjo1vazCOg'
-- WHERE campaign_id = '8e4eb33d-0fae-439b-823f-d5354cb8564d'
--   AND status NOT IN ('completed', 'cancelled')
--   AND assigned_to_user_id = 'user_3GB6YKt8YZCaNu0QWqbuC50dtct';

-- Verify:
-- SELECT id, user_id FROM campaigns WHERE id = '8e4eb33d-0fae-439b-823f-d5354cb8564d';
--   -> user_39RB7n4XAbFpCbwdVEjo1vazCOg
-- SELECT dispatch_suspended, dispatch_suspended_reason FROM organization
-- WHERE id = 'org_33rpyiDYRk4cfqGLqE0Olc27ptl';
--   -> false, NULL
-- Rollback (campaign owner; re-run step 1 first if the mailbox migration is being reverted too):
-- UPDATE campaigns SET user_id = 'user_3GB6YKt8YZCaNu0QWqbuC50dtct'
-- WHERE id = '8e4eb33d-0fae-439b-823f-d5354cb8564d'
--   AND user_id = 'user_39RB7n4XAbFpCbwdVEjo1vazCOg';
