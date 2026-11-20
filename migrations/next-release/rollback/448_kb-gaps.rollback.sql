-- Reverses 448. Deploy the Modal and app commits before kb gaps first (or set the engine switch to 0 and the app's
-- kbGapsEnabled() off): the engine calls record_kb_gap and the app reads kb_gaps; while they are gone the engine
-- logs PGRST202 once per process and records nothing, and the app's gap list is empty. Lossy: every recorded gap,
-- its counts and statuses go with the tables.
SET LOCAL lock_timeout = '10s';

DROP FUNCTION IF EXISTS public.set_kb_gap_status(text, uuid, text, uuid, text);
DROP FUNCTION IF EXISTS public.record_kb_gap(text, uuid, text, text, text, text, text, text, uuid, text);
DROP TABLE IF EXISTS public.kb_gap_events;
DROP TABLE IF EXISTS public.kb_gaps;
