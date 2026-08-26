-- ============================================================
-- Migration: 367_crm-deal-notes-and-stage-reasons
-- Date:      2026-08-26
-- Purpose:   Make contact_notes the canonical deal-note store and preserve an
--            optional human reason on audited deal-stage changes.
-- Projects:  selltonai-database/supabase (owner), selltonai (caller),
--            selltonai-modal (reader).
-- Contract:  Additive service-role RPCs. The existing four-argument
--            update_crm_deal contract remains unchanged.
-- Depends:   349_crm-deals-foundation.sql.
-- ============================================================

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
    TRUE
  )
  RETURNING * INTO v_activity;

  RETURN v_activity;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_crm_deal(
  p_deal_id UUID,
  p_organization_id TEXT,
  p_actor_user_id TEXT,
  p_changes JSONB,
  p_reason TEXT
)
RETURNS public.deals
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_previous_stage TEXT;
  v_deal public.deals;
  v_reason TEXT := NULLIF(BTRIM(p_reason), '');
BEGIN
  IF v_reason IS NOT NULL AND LENGTH(v_reason) > 2000 THEN
    RAISE EXCEPTION 'Deal stage reason cannot exceed 2000 characters'
      USING ERRCODE = '22023';
  END IF;

  IF v_reason IS NOT NULL AND NOT COALESCE(p_changes ? 'stage', FALSE) THEN
    RAISE EXCEPTION 'A deal stage reason requires a stage change'
      USING ERRCODE = '22023';
  END IF;

  SELECT d.stage
  INTO v_previous_stage
  FROM public.deals d
  WHERE d.id = p_deal_id
    AND d.organization_id = p_organization_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Deal not found' USING ERRCODE = 'P0002';
  END IF;

  SELECT *
  INTO v_deal
  FROM public.update_crm_deal(p_deal_id, p_organization_id, p_actor_user_id, p_changes);

  IF v_reason IS NOT NULL AND v_deal.stage IS DISTINCT FROM v_previous_stage THEN
    UPDATE public.deal_activities activity
    SET metadata = activity.metadata || JSONB_BUILD_OBJECT('reason', v_reason)
    WHERE activity.id = (
      SELECT candidate.id
      FROM public.deal_activities candidate
      WHERE candidate.deal_id = p_deal_id
        AND candidate.organization_id = p_organization_id
        AND candidate.activity_type = 'stage_change'
        AND candidate.metadata->>'from' = v_previous_stage
        AND candidate.metadata->>'to' = v_deal.stage
      ORDER BY candidate.created_at DESC, candidate.id DESC
      LIMIT 1
    );
  END IF;

  RETURN v_deal;
END;
$$;

REVOKE ALL ON FUNCTION public.add_crm_deal_note(UUID, TEXT, TEXT, TEXT)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.update_crm_deal(UUID, TEXT, TEXT, JSONB, TEXT)
  FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.add_crm_deal_note(UUID, TEXT, TEXT, TEXT)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.update_crm_deal(UUID, TEXT, TEXT, JSONB, TEXT)
  TO service_role;

COMMENT ON FUNCTION public.add_crm_deal_note(UUID, TEXT, TEXT, TEXT) IS
  'Atomically writes a deal note to canonical contact_notes and its deal timeline audit row.';
COMMENT ON FUNCTION public.update_crm_deal(UUID, TEXT, TEXT, JSONB, TEXT) IS
  'Service-role deal mutation with an optional human stage-change reason stored in stage_change activity metadata.';
