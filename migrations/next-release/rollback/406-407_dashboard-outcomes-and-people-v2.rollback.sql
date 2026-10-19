-- Reverses 406 and 407. Both are read-only functions; the dashboard reader falls back (406: "-" and the
-- "Some numbers could not load" notice; 407: v1, without the across-channels figure), so this can run at any time.
DROP FUNCTION IF EXISTS public.dashboard_people_reply_rollup_v2(text, timestamptz, timestamptz, text);
DROP FUNCTION IF EXISTS public.dashboard_outcomes_v1(text, timestamptz, timestamptz, text);
