-- Reverses 437. Deploy the Modal and app commits before this release first: the app writes and selects the column
-- and fails a play save while it is gone; Modal before this release reads the metadata key, which 437 left in place.
-- Lossy: a play's own fields saved after 437 live only in the column and go with it (the play follows its profile
-- again until they are saved once more). The table comments go back to 435's words.
SET LOCAL lock_timeout = '10s';

ALTER TABLE public.campaigns DROP COLUMN IF EXISTS play_own_targeting;

COMMENT ON TABLE public.people_search_requests IS
  'Roles added to a launched play, one row per save (the added titles only). requested_by is the Clerk user id. company_ids: the play''s approved companies, written once by the first cron run; a company approved later takes the normal path, which already searches the play''s roles. status pending until every listed company has a people_search_request_companies row (done, outcome completed) or the play is on the rep''s existing connections or cancelled (excluded).';

COMMENT ON TABLE public.people_search_request_companies IS
  'A company of a people_search_requests row. Inserted (the claim) before the search is paid for; the primary key makes the claim atomic. A row with done_at NULL is a claim whose run stopped: it stays taken and is never paid for again. A release deletes the row.';
