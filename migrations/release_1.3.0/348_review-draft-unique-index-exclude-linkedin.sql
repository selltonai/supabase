-- 348 — Stop the EMAIL first-draft unique index from blocking LinkedIn tasks.
--
-- The bug (observed in production):
--   campaign_sequence_actions rows with
--     action_type = 'linkedin_invitation', status = 'failed',
--     last_error  = 'task_create_failed: duplicate key value violates unique
--                    constraint "idx_tasks_review_draft_unique_first_email"'
--   i.e. a contact's LinkedIn INVITE task could not be created, the action
--   retried 3 times and died — that contact silently never gets invited.
--
-- Why it happens:
--   Migration 178 (release_1.0.2, written before LinkedIn existed) added
--     UNIQUE (contact_id, organization_id)
--     WHERE task_type='review_draft' AND status='pending' AND thread_id IS NULL
--   to enforce "one pending FIRST-EMAIL draft per contact".
--   LinkedIn review tasks are ALSO task_type='review_draft', status='pending',
--   thread_id NULL — they are distinguished only by metadata->>'channel'
--   = 'linkedin'. So the email-only invariant catches LinkedIn tasks too:
--     - a contact with a pending EMAIL draft blocks their LinkedIn invite task;
--     - a LinkedIn invite task blocks a later LinkedIn task for that contact;
--     - the same contact in an email AND a LinkedIn campaign collides.
--
-- The fix:
--   Re-create the index with the SAME predicate plus an exclusion for LinkedIn
--   rows. Email behaviour is bit-for-bit unchanged (a NULL metadata or a NULL
--   channel is still covered — `IS DISTINCT FROM` treats NULL as "not
--   linkedin", matching how the email path has always been indexed).
--
--   Deliberately NOT adding an equivalent LinkedIn uniqueness rule here: the
--   LinkedIn sequence is serial per journey and already has its own dedupe
--   (enrol tier-1/tier-2 + the claim lease), so inventing a new DB-level
--   constraint for it would be a behaviour change, not a bug fix.
--
-- Affected projects:
--   - selltonai: the sequence claimer's task insert stops failing for LinkedIn.
--   - No application change ships with this; it is purely corrective DDL.
--
-- Rollback: re-create the index without the metadata predicate (the 178 form).
--
-- NOTE: no CREATE INDEX CONCURRENTLY — the migration runner rejects it, and
-- `tasks` is small enough that a brief lock in the deploy window is acceptable.

DROP INDEX IF EXISTS public.idx_tasks_review_draft_unique_first_email;

CREATE UNIQUE INDEX IF NOT EXISTS idx_tasks_review_draft_unique_first_email
ON public.tasks (contact_id, organization_id)
WHERE task_type = 'review_draft'
  AND status = 'pending'
  AND thread_id IS NULL
  AND (metadata->>'channel') IS DISTINCT FROM 'linkedin';

COMMENT ON INDEX public.idx_tasks_review_draft_unique_first_email IS
  'Ensures only one pending first-EMAIL review_draft task per contact. Excludes replies (thread_id set) and, since migration 348, excludes LinkedIn tasks (metadata->>channel = linkedin) — LinkedIn reuses task_type=review_draft, so the email invariant was blocking LinkedIn invite task creation and silently killing those invitations.';

-- Verify (expect 0 rows — no LinkedIn task should be covered by the index):
--   SELECT count(*) FROM public.tasks
--    WHERE task_type = 'review_draft' AND status = 'pending'
--      AND thread_id IS NULL AND metadata->>'channel' = 'linkedin';
--
-- And confirm the email invariant still holds (expect 0 rows):
--   SELECT contact_id, organization_id, count(*)
--     FROM public.tasks
--    WHERE task_type = 'review_draft' AND status = 'pending'
--      AND thread_id IS NULL
--      AND (metadata->>'channel') IS DISTINCT FROM 'linkedin'
--    GROUP BY 1, 2 HAVING count(*) > 1;
