-- Reverses 430. Touches only the engine_* objects; the mobile_* ones are never involved.
-- Lossy once rows exist: dropping the tables drops the engine's queue and its send counters. Check first:
--   SELECT (SELECT count(*) FROM public.engine_actions) AS actions,
--          (SELECT count(*) FROM public.engine_send_counters) AS counters;
-- Do not roll back while the engine's workers run against these tables (after E-M0 step 3).
SET LOCAL lock_timeout = '10s';
DROP TRIGGER IF EXISTS engine_send_counters_updated_at ON public.engine_send_counters;
DROP TRIGGER IF EXISTS engine_actions_updated_at ON public.engine_actions;
DROP FUNCTION IF EXISTS public.update_engine_send_counters_updated_at();
DROP FUNCTION IF EXISTS public.update_engine_actions_updated_at();
DROP FUNCTION IF EXISTS public.engine_reserve_sends(text, text, date, integer, integer);
DROP TABLE IF EXISTS public.engine_send_counters;
DROP TABLE IF EXISTS public.engine_actions;
