-- KAN-282 F4: record the handoff when an inbound reply stops outbound work.
-- This operational event must not move deals' last_activity_at.
CREATE OR REPLACE FUNCTION public.record_crm_deal_activity_for_contact(
  p_organization_id TEXT, p_contact_id UUID, p_activity_type TEXT, p_title TEXT,
  p_source_event_key TEXT, p_metadata JSONB DEFAULT '{}'::JSONB,
  p_occurred_at TIMESTAMPTZ DEFAULT NOW(), p_actor TEXT DEFAULT 'system',
  p_actor_user_id TEXT DEFAULT NULL
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_deal_id UUID; v_activity_id UUID;
BEGIN
  IF p_activity_type NOT IN ('email_in','email_out','linkedin_in','linkedin_out','sequence_stopped','linkedin_connected') THEN
    RAISE EXCEPTION 'Unsupported projected activity type: %', p_activity_type USING ERRCODE = '22023';
  END IF;
  IF p_actor NOT IN ('system','user') THEN
    RAISE EXCEPTION 'Unsupported activity actor: %', p_actor USING ERRCODE = '22023';
  END IF;
  IF NULLIF(BTRIM(p_source_event_key), '') IS NULL THEN
    RAISE EXCEPTION 'A stable source event key is required' USING ERRCODE = '22023';
  END IF;
  SELECT d.id INTO v_deal_id FROM public.deals d
  JOIN public.company_contacts cc ON cc.company_id=d.company_id AND cc.organization_id=d.organization_id
  WHERE d.organization_id=p_organization_id AND d.closed_at IS NULL AND cc.contact_id=p_contact_id
  ORDER BY (d.primary_contact_id=p_contact_id) DESC, d.stage_updated_at DESC, d.id LIMIT 1;
  IF v_deal_id IS NULL THEN RETURN NULL; END IF;
  INSERT INTO public.deal_activities
    (deal_id,organization_id,activity_type,actor,actor_user_id,contact_id,title,metadata,bumps_last_activity,source_event_key,created_at)
  VALUES (v_deal_id,p_organization_id,p_activity_type,p_actor,
    CASE WHEN p_actor='user' THEN p_actor_user_id ELSE NULL END,p_contact_id,
    COALESCE(NULLIF(BTRIM(p_title),''),'Deal activity'),COALESCE(p_metadata,'{}'::JSONB),
    p_activity_type NOT IN ('sequence_stopped'),BTRIM(p_source_event_key),COALESCE(p_occurred_at,NOW()))
  ON CONFLICT (organization_id,source_event_key) WHERE source_event_key IS NOT NULL DO NOTHING
  RETURNING id INTO v_activity_id;
  IF v_activity_id IS NULL THEN
    SELECT id INTO v_activity_id FROM public.deal_activities
    WHERE organization_id=p_organization_id AND source_event_key=BTRIM(p_source_event_key);
    IF NOT EXISTS (SELECT 1 FROM public.deal_activities da WHERE da.id=v_activity_id
      AND da.deal_id=v_deal_id AND da.contact_id=p_contact_id AND da.activity_type=p_activity_type) THEN
      RAISE EXCEPTION 'Source event key already belongs to a different CRM activity envelope' USING ERRCODE = '23505';
    END IF;
  END IF;
  RETURN v_activity_id;
END; $$;
REVOKE ALL ON FUNCTION public.record_crm_deal_activity_for_contact(TEXT,UUID,TEXT,TEXT,TEXT,JSONB,TIMESTAMPTZ,TEXT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_crm_deal_activity_for_contact(TEXT,UUID,TEXT,TEXT,TEXT,JSONB,TIMESTAMPTZ,TEXT,TEXT) TO service_role;
