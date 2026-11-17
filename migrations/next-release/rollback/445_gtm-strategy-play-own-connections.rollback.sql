-- Reverses 445: the column is dropped and every Strategist LinkedIn play starts as new connections again. The Modal
-- code then stores plays without it (it retries the insert without the column), so it may stay live.
SET LOCAL lock_timeout = '10s';

ALTER TABLE public.gtm_strategy_plays
  DROP COLUMN IF EXISTS own_connections;
