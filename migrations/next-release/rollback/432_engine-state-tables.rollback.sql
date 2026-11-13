-- Reverses 432. Lossy once rows exist: chat lines and feedback are kept for improving Sellton, limits and pacing are
-- live state. Copy the tables first if they hold rows, and do not roll back while the engine reads them (after E-M1).
SET LOCAL lock_timeout = '10s';
DROP TABLE IF EXISTS public.engine_feedback;
DROP TABLE IF EXISTS public.engine_chat_lines;
DROP TABLE IF EXISTS public.engine_workers;
DROP TABLE IF EXISTS public.engine_pacing;
DROP TABLE IF EXISTS public.engine_limits;
DROP FUNCTION IF EXISTS public.engine_set_updated_at();
