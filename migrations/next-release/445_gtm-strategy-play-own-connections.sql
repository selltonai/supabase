-- ============================================================
-- Migration: 445_gtm-strategy-play-own-connections
-- Date:      2026-11-17
-- Purpose:   The Strategist's choice of a LinkedIn play's audience is kept (PLAN_STRATEGIST_ROUND_3_AND_ASK_RULE
--            _2026_11_17.md, B1). The Strategist chooses email, linkedin_new or linkedin_first_degree; the play is
--            stored with channel email or linkedin only (438), so a play to the rep's own connections was lost and
--            every Strategist LinkedIn draft started as a play to new connections.
--            1. gtm_strategy_plays.own_connections boolean, nullable: true for a play to the rep's own connections,
--               false for a play to new people, null for an email play and for every play stored before this.
--            Nothing is backfilled: plays already stored keep starting as new connections (B3).
-- Projects:  selltonai-database/supabase (owner); selltonai-modal writes and returns the column (gtm_strategy_run);
--            selltonai reads it on the play and creates the draft as a play to own connections (B2).
-- Contract:  A new nullable column only; 438's channel check is unchanged. The Modal code stores plays without the
--            column when it is missing, so the order is safe either way. Goes first (merge order: this, then Modal
--            fix/strategist-round-3, then app fix/strategist-own-connections).
-- Depends:   public.gtm_strategy_plays (438).
-- Rollback:  rollback/445_gtm-strategy-play-own-connections.rollback.sql
-- ============================================================

SET LOCAL lock_timeout = '10s';

ALTER TABLE public.gtm_strategy_plays
  ADD COLUMN IF NOT EXISTS own_connections boolean;

COMMENT ON COLUMN public.gtm_strategy_plays.own_connections IS
  'The Strategist''s audience of a LinkedIn play: true = the rep''s own connections, false = new people, null = email or stored before 445.';
