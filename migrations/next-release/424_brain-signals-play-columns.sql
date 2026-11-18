-- ============================================================
-- Migration: 424_brain-signals-play-columns
-- Date:      2026-11-11
-- Purpose:   Brain signals in plays (PLAN_BRAIN_SIGNALS_PLAY_FIXES_2026_11_11.md, P5 and P6).
--            1. company_signal_workspace.goal_campaign_id: the play the router graded the signal against, set when
--               goal_source is 'play', NULL otherwise (P5). The play judge trusts the grade only for that same play.
--            2. company_signal_contact_use.step_key: the LinkedIn step a use belongs to (play, action type, step
--               number), so one step writes one use however often it is drawn and two steps are two uses (P6).
--               NULL for email uses, which hang on their task.
-- Projects:  selltonai-database/supabase (owner); selltonai-modal writes both (the signal router writes
--            goal_campaign_id, the LinkedIn writer helper writes step_key) and reads both (the play judge, the use
--            count). selltonai does not read them.
-- Contract:  Additive only, two nullable columns, no default, no index: rows written before this stay NULL and are
--            judged and counted as today. Goes before the Modal PRs (merge order: this, the router PR, the writers PR).
-- Depends:   public.company_signal_workspace, public.company_signal_contact_use (421), public.campaigns.
-- Rollback:  rollback/424_brain-signals-play-columns.rollback.sql
-- ============================================================

SET LOCAL lock_timeout = '10s';

-- 1. The play a grade was given against (P5) -----------------------------------------------------

ALTER TABLE public.company_signal_workspace
  ADD COLUMN IF NOT EXISTS goal_campaign_id uuid;

COMMENT ON COLUMN public.company_signal_workspace.goal_campaign_id IS
  'The play (campaigns.id) whose goal the router graded this signal against; set only when goal_source = ''play'', NULL otherwise (P5). No foreign key: a deleted play leaves the id, and the judge then finds no match and judges as today.';

-- 2. The LinkedIn step a use belongs to (P6) -----------------------------------------------------

ALTER TABLE public.company_signal_contact_use
  ADD COLUMN IF NOT EXISTS step_key text;

COMMENT ON COLUMN public.company_signal_contact_use.step_key IS
  'The LinkedIn step this use belongs to (play, action type, step number), written by the LinkedIn writer (P6). NULL for email uses (they hang on task_id) and for rows written before 424.';

-- Verify:
-- select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'company_signal_workspace';
--   -> 12
-- select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'company_signal_contact_use';
--   -> 7
