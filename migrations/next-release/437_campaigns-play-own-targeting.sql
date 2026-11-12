-- ============================================================
-- Migration: 437_campaigns-play-own-targeting
-- Date:      2026-11-12
-- Purpose:   Two small gaps of the roles search (PLAN_RELEASE_PROD_ROLES_SEARCH_2026_11_12.md section 12;
--            Borce 2026-11-12: "the small gaps, the company needs to be resumed not dropped").
--            1. campaigns.play_own_targeting: which of job_titles, company_size and regions a play with an ICP
--               profile set for itself (F2). It sat in campaigns.metadata.play_own_targeting, and other writers
--               of metadata write whole copies, so it could be dropped and the play would silently read its
--               profile again. NULL means none. The existing metadata values are copied once, below.
--            2. The comments of 435's two tables now say when a request closes: only when every company of it
--               has a row with done_at set. A row with done_at NULL is a claim in flight; Modal releases one
--               older than its stale window, so the company is taken again.
-- Projects:  selltonai-database/supabase (owner); selltonai writes the column (the play edit page's save);
--            selltonai-modal reads it (campaign_service.play_own_targeting), and reads the metadata key only
--            while the column is NULL.
-- Contract:  Additive only. The metadata key stays where it is (Modal before this release still reads it); the
--            app stops writing it.
--            Merge order: this, then Modal, then the app.
-- Depends:   public.campaigns; 435 (people_search_requests, people_search_request_companies).
-- Rollback:  rollback/437_campaigns-play-own-targeting.rollback.sql
-- ============================================================

SET LOCAL lock_timeout = '10s';

-- 1. The column ----------------------------------------------------------------------------------

ALTER TABLE public.campaigns
  ADD COLUMN IF NOT EXISTS play_own_targeting text[];

COMMENT ON COLUMN public.campaigns.play_own_targeting IS
  'Which of job_titles, company_size and regions a play with an ICP profile set for itself on the edit page. A listed field is read from the play''s own columns instead of the profile, for this play only; the profile row is never changed. NULL: none, the play follows its profile. Written by the app''s play save route only.';

-- The one-time copy: only lists, only the three known names (each once, in the app's order), only where the
-- column is still empty. A value that is not a list reads as an empty one, so it copies nothing.
UPDATE public.campaigns AS c
SET play_own_targeting = copied.fields
FROM (
  SELECT listed.id,
         array_agg(listed.field ORDER BY array_position(ARRAY['job_titles', 'company_size', 'regions'], listed.field)) AS fields
  FROM (
    SELECT DISTINCT campaigns.id, element.field
    FROM public.campaigns,
         LATERAL jsonb_array_elements_text(
           CASE WHEN jsonb_typeof(campaigns.metadata -> 'play_own_targeting') = 'array'
                THEN campaigns.metadata -> 'play_own_targeting'
                ELSE '[]'::jsonb END
         ) AS element(field)
    WHERE element.field IN ('job_titles', 'company_size', 'regions')
  ) AS listed
  GROUP BY listed.id
) AS copied
WHERE c.id = copied.id
  AND c.play_own_targeting IS NULL;

-- 2. When a roles request closes -----------------------------------------------------------------

COMMENT ON TABLE public.people_search_requests IS
  'Roles added to a launched play, one row per save (the added titles only). requested_by is the Clerk user id. company_ids: the play''s approved companies, written once by the first cron run; a company approved later takes the normal path, which already searches the play''s roles. status pending until every listed company has a people_search_request_companies row with done_at set (done, outcome completed) or the play is on the rep''s existing connections or cancelled (excluded). A released company has no row, so its request stays pending and a later run takes it again.';

COMMENT ON TABLE public.people_search_request_companies IS
  'A company of a people_search_requests row. Inserted (the claim) before the search is paid for; the primary key makes the claim atomic. done_at is set once the company is searched, failed or skipped, and such a row is never taken again. A row with done_at NULL is a claim in flight; Modal deletes one older than its stale window (well above the cron timeout), so the company is taken again. A release (spend limit, AI Ark unavailable) deletes the row.';

-- Verify:
-- select data_type from information_schema.columns where table_schema = 'public' and table_name = 'campaigns' and column_name = 'play_own_targeting';
--   -> ARRAY
-- select count(*) from public.campaigns where jsonb_typeof(metadata -> 'play_own_targeting') = 'array' and play_own_targeting is null;
--   -> 0, unless a play's list held none of the three names
