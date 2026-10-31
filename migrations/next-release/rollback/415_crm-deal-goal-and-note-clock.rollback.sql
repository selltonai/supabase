-- Reverses 415. The app reads deals.goal only when present, so this can run while the app is live; deals then lose
-- the goals their owners set. add_crm_deal_note goes back to moving last_activity_at on a note (367 as written).
ALTER TABLE public.deals
  DROP CONSTRAINT IF EXISTS deals_goal_length_check;
ALTER TABLE public.deals
  DROP COLUMN IF EXISTS goal;

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
