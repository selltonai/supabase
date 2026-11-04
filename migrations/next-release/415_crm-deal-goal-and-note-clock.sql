-- ============================================================
-- Migration: 415_crm-deal-goal-and-note-clock
-- Date:      2026-10-31
-- Purpose:   CRM quiet deals (PLAN_CRM_QUIET_DEALS_TASKS_2026_10_31.md in the Sellton planning folder).
--            F6: deals.goal, the owner's own goal for one deal (for example "sign an NDA with them"). When set it
--                replaces the play's goal in every CRM follow-up prompt and in the call note. NULL = use the play goal.
--            F7: a deal note no longer moves deals.last_activity_at. A note is the owner's own record, not a customer
--                touch, so adding one must not push the next quiet-deal follow-up 14 days away. Calls, emails,
--                LinkedIn messages and replies still move it.
-- Projects:  selltonai-database/supabase (owner); selltonai writes goal from the deal drawer (PATCH /api/deals/[id]);
--            selltonai-modal reads it through select("*") on deals (deal_nurture_service, call_task_automation).
-- Contract:  Additive column, nullable, no backfill. add_crm_deal_note keeps its signature, grants and return value;
--            only the activity row's bumps_last_activity changes from TRUE to FALSE. Existing rows are unchanged.
-- Depends:   349_crm-deals-foundation.sql, 367_crm-deal-notes-and-stage-reasons.sql.
-- Rollback:  rollback/415_crm-deal-goal-and-note-clock.rollback.sql
-- ============================================================

ALTER TABLE public.deals
  ADD COLUMN IF NOT EXISTS goal TEXT;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'deals_goal_length_check'
  ) THEN
    ALTER TABLE public.deals
      ADD CONSTRAINT deals_goal_length_check CHECK (goal IS NULL OR LENGTH(goal) <= 2000);
  END IF;
END $$;

COMMENT ON COLUMN public.deals.goal IS
  'The owner''s goal for this deal. When set it replaces the source play''s goal in CRM follow-ups and call notes. NULL = the play goal.';

CREATE OR REPLACE FUNCTION public.add_crm_deal_note(
  p_deal_id UUID,
  p_organization_id TEXT,
  p_actor_user_id TEXT,
  p_content TEXT
)
RETURNS public.deal_activities
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_primary_contact_id UUID;
  v_contact_note_id UUID;
  v_activity public.deal_activities;
BEGIN
  IF NULLIF(BTRIM(p_content), '') IS NULL OR LENGTH(BTRIM(p_content)) > 5000 THEN
    RAISE EXCEPTION 'Deal note must contain between 1 and 5000 characters'
      USING ERRCODE = '22023';
  END IF;

  SELECT d.primary_contact_id
  INTO v_primary_contact_id
  FROM public.deals d
  WHERE d.id = p_deal_id
    AND d.organization_id = p_organization_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Deal not found' USING ERRCODE = 'P0002';
  END IF;

  IF v_primary_contact_id IS NULL THEN
    RAISE EXCEPTION 'A primary contact is required before adding a deal note'
      USING ERRCODE = '23514';
  END IF;

  IF p_actor_user_id IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM public.user_organizations uo
    WHERE uo.organization_id = p_organization_id
      AND uo.user_id = p_actor_user_id
  ) THEN
    RAISE EXCEPTION 'Deal actor is not an organization member'
      USING ERRCODE = '23514';
  END IF;

  INSERT INTO public.contact_notes (
    contact_id, organization_id, user_id, content, note_type, is_pinned
  ) VALUES (
    v_primary_contact_id, p_organization_id, p_actor_user_id,
    BTRIM(p_content), 'deal', FALSE
  )
  RETURNING id INTO v_contact_note_id;

  INSERT INTO public.deal_activities (
    deal_id, organization_id, activity_type, actor, actor_user_id, contact_id,
    title, metadata, bumps_last_activity
  ) VALUES (
    p_deal_id, p_organization_id, 'note', 'user', p_actor_user_id,
    v_primary_contact_id, 'Note added',
    JSONB_BUILD_OBJECT('content', BTRIM(p_content), 'contact_note_id', v_contact_note_id),
    FALSE
  )
  RETURNING * INTO v_activity;

  RETURN v_activity;
END;
$$;
