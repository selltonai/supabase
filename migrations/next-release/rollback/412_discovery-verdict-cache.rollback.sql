-- Reverses 412. The Modal code tolerates the missing table and column (it logs and goes on):
-- every press then fetches and judges again, and old market rejections count as before.
ALTER TABLE public.discovery_rejections
  DROP COLUMN IF EXISTS prompt_version;
DROP TABLE IF EXISTS public.discovery_verdict_cache;
