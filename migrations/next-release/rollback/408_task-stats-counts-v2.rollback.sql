-- Reverses 408. The BFF falls back to task_stats_counts_v1 (386) when v2 is missing (logged), so this is safe while
-- the route is live; the counts then use v1's rule again, and the Tasks tabs show "-" under a due filter.
DROP FUNCTION IF EXISTS public.task_stats_counts_v2(text, text, text, text, uuid, uuid, uuid, boolean, text, text, text, timestamptz, timestamptz);
