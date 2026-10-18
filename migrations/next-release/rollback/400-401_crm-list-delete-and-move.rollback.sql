-- Reverses 400 and 401 (KAN-334). To apply: copy to the next free number in next-release/ and list it in the
-- deploy manifest; the ledger refuses a changed file, so 400/401 themselves are never edited.
-- Roll back Modal and the frontend first: the old apps do not call these functions.
--
-- Kept on purpose: crm_lists.delete_state, crm_list_delete_jobs and the campaign_companies move columns
-- (nullable, unused by the old apps, and they keep the history). The seven indexes are harmless; drop them
-- only if one of them causes a problem.

SET LOCAL lock_timeout = '5s';

DROP FUNCTION IF EXISTS public.crm_list_delete_batch(text, uuid, integer);
DROP FUNCTION IF EXISTS public.crm_list_delete_preview(text, uuid);
DROP FUNCTION IF EXISTS public.move_company_review(text, uuid, uuid, uuid, text);

-- A list left in 'deleting' by a stopped job would stay hidden in the new UI; the old UI ignores the column.
UPDATE public.crm_lists SET delete_state = NULL WHERE delete_state IS NOT NULL;

-- Optional, only if an index is the problem:
-- DROP INDEX IF EXISTS public.idx_ai_ark_enrollment_runs_company_id;
-- DROP INDEX IF EXISTS public.idx_deals_company_id;
-- DROP INDEX IF EXISTS public.idx_unmatched_replies_resolved_company_id;
-- DROP INDEX IF EXISTS public.idx_deal_activities_contact_id;
-- DROP INDEX IF EXISTS public.idx_deals_stage_contact_id;
-- DROP INDEX IF EXISTS public.idx_crm_deal_projection_failures_contact_id;
-- DROP INDEX IF EXISTS public.idx_unmatched_replies_resolved_contact_id;
