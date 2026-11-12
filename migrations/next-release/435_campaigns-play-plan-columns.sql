-- ============================================================
-- Migration: 435_campaigns-play-plan-columns
-- Date:      2026-11-12
-- Purpose:   Play plan (PLAN_PLAY_BRIEF_TO_SEQUENCE_2026_11_11.md, decisions of 2026-11-12): own storage for the play's
--            conversation plan and the play's LinkedIn invitation lines. Today both sit as keys inside the
--            campaigns.campaign_goal JSON (campaign_goal.conversation_plan, campaign_goal.note_lines).
--              1. campaigns.conversation_plan jsonb, null: the plan the backend writes when it reads the play's brief.
--              2. campaigns.note_lines jsonb, null: the play's LinkedIn invitation lines.
--              3. Backfill: each new column is filled from the matching key of campaign_goal where the column is still
--                 null and the key is a JSON object. campaign_goal is jsonb (280, 310); a row whose campaign_goal is
--                 null, a JSON null, empty, a scalar or an array is skipped without error.
--            The keys STAY in campaign_goal. The backend removes them on its next write of the goal; until then the
--            readers prefer the column and fall back to the key.
--            The backfill UPDATE must not touch updated_at (play lists, the dashboard and the crons order by it), so the
--            updated_at trigger (update_campaigns_updated_at, 38) is switched off for the backfill only and switched on
--            again in the same transaction, when it exists. The other campaigns triggers (updated_at aside:
--            trigger_update_selected_company_ids on curated_companies; 411 on status and name) do not fire on this UPDATE.
-- Projects:  selltonai-database/supabase (owner); selltonai-modal writes and reads both columns; selltonai (app) reads them.
-- Contract:  Additive only: two nullable columns, no default, no index, no constraint. No view, function or policy
--            changes. Idempotent: ADD COLUMN IF NOT EXISTS; the backfill only touches rows where the column is null.
--            Merge order: this PR (supabase), then the selltonai-modal play plan PR, then the selltonai app play plan PR.
-- Rollback:  rollback/435_campaigns-play-plan-columns.rollback.sql (drops the two columns; the keys in campaign_goal
--            still hold the data until the backend has removed them).
-- ============================================================

SET LOCAL lock_timeout = '10s';

ALTER TABLE public.campaigns
  ADD COLUMN IF NOT EXISTS conversation_plan jsonb,
  ADD COLUMN IF NOT EXISTS note_lines jsonb;

COMMENT ON COLUMN public.campaigns.conversation_plan IS
  'The play''s conversation plan (JSON object), written by the backend when it reads the play''s brief. Null: no plan stored. Before 435 it lived in campaign_goal.conversation_plan.';
COMMENT ON COLUMN public.campaigns.note_lines IS
  'The play''s LinkedIn invitation lines (JSON object), written by the backend. Null: none stored. Before 435 they lived in campaign_goal.note_lines.';

DO $$
DECLARE
  v_trigger_on boolean;
BEGIN
  -- Keep updated_at as it is: switch the updated_at trigger off for this backfill only.
  SELECT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgrelid = 'public.campaigns'::regclass
      AND tgname = 'update_campaigns_updated_at'
      AND NOT tgisinternal
      AND tgenabled <> 'D'
  ) INTO v_trigger_on;

  IF v_trigger_on THEN
    EXECUTE 'ALTER TABLE public.campaigns DISABLE TRIGGER update_campaigns_updated_at';
  END IF;

  UPDATE public.campaigns
  SET conversation_plan = campaign_goal -> 'conversation_plan'
  WHERE conversation_plan IS NULL
    AND jsonb_typeof(campaign_goal) = 'object'
    AND jsonb_typeof(campaign_goal -> 'conversation_plan') = 'object';

  UPDATE public.campaigns
  SET note_lines = campaign_goal -> 'note_lines'
  WHERE note_lines IS NULL
    AND jsonb_typeof(campaign_goal) = 'object'
    AND jsonb_typeof(campaign_goal -> 'note_lines') = 'object';

  IF v_trigger_on THEN
    EXECUTE 'ALTER TABLE public.campaigns ENABLE TRIGGER update_campaigns_updated_at';
  END IF;
END $$;

-- Verify
DO $$
BEGIN
  IF (
    SELECT count(*) FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'campaigns'
      AND column_name IN ('conversation_plan', 'note_lines') AND data_type = 'jsonb'
  ) <> 2 THEN
    RAISE EXCEPTION '435: campaigns.conversation_plan and campaigns.note_lines (jsonb) are not both present';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgrelid = 'public.campaigns'::regclass
      AND tgname = 'update_campaigns_updated_at' AND tgenabled = 'D'
  ) THEN
    RAISE EXCEPTION '435: update_campaigns_updated_at was left disabled';
  END IF;
END $$;
