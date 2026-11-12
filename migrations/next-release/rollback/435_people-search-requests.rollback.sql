-- Reverses 435. Deploy the Modal and app commits before the roles queue table first (or set
-- PEOPLE_RESEARCH_CRON_ENABLED=0): the cron and the save route read and write these tables and log an error while
-- they are gone. Lossy: open requests and the record of searched companies go with the tables.
SET LOCAL lock_timeout = '10s';

DROP TABLE IF EXISTS public.people_search_request_companies;
DROP TABLE IF EXISTS public.people_search_requests;
