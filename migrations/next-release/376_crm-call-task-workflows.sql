-- KAN-305: atomic call note/task creation, lifecycle safety and one-day snooze.
-- Affected: selltonai BFF/UI, selltonai-modal creation/notifications; deploy DB first.
-- Depends: committed 375 and CRM workflows352/contact holds366.
-- RPCs are service-role-only. Authenticated BFF/backend MUST enforce owner or
-- manager permissions; DB validates actor/owner membership and all tenant links.
-- stop_drafts alone is a sender boundary, not a hard hold (migration366).

-- Extend the currently installed CHECK instead of deleting other branch values.
DO $$
DECLARE v_expression text;
BEGIN
  SELECT pg_get_expr(conbin, conrelid) INTO STRICT v_expression
  FROM pg_constraint WHERE conrelid='public.notifications'::regclass
    AND conname='notifications_type_check';
  IF position('call_due' IN v_expression)=0 THEN
    ALTER TABLE public.notifications DROP CONSTRAINT notifications_type_check;
    EXECUTE 'ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check CHECK ((' || v_expression || ') OR type = ''call_due'')';
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS idx_tasks_one_open_call_per_deal
ON public.tasks(deal_id)
WHERE deal_id IS NOT NULL AND task_type='call'::public.task_type
  AND status IN ('pending'::public.task_status,'in_progress'::public.task_status,'scheduled'::public.task_status,'in_review'::public.task_status);

CREATE OR REPLACE FUNCTION public.validate_crm_call_task()
RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE v_deal public.deals; v_contact public.contacts;
BEGIN
  IF TG_OP='UPDATE' AND OLD.task_type='call'::public.task_type AND NEW.task_type IS DISTINCT FROM OLD.task_type THEN
    RAISE EXCEPTION 'A call cannot change to a sending task type' USING ERRCODE='23514';
  END IF;
  IF NEW.task_type IS DISTINCT FROM 'call'::public.task_type THEN RETURN NEW; END IF;
  IF TG_OP='UPDATE' AND OLD.status IN ('completed','cancelled','rejected') AND NEW.status IS DISTINCT FROM OLD.status THEN
    RAISE EXCEPTION 'A finished call cannot be reopened' USING ERRCODE='23514';
  END IF;
  IF NEW.status IS NULL OR NEW.status NOT IN ('pending','completed','cancelled','rejected')
    OR COALESCE(NEW.scheduled,false) OR COALESCE(NEW.send_status,'not_sent')<>'not_sent' THEN
    RAISE EXCEPTION 'Calls cannot be approved or dispatched' USING ERRCODE='23514';
  END IF;
  -- FK SET NULL is part of contact/deal deletion; retain cancelled history.
  IF NEW.deal_id IS NULL OR NEW.contact_id IS NULL THEN
    IF TG_OP='UPDATE' AND (NEW.deal_id IS NULL AND (OLD.deal_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.deals WHERE id=OLD.deal_id))
      OR NEW.contact_id IS NULL AND (OLD.contact_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.contacts WHERE id=OLD.contact_id))) THEN
      IF NEW.status NOT IN ('completed','cancelled','rejected') THEN NEW.status := 'cancelled'; END IF;
      RETURN NEW;
    END IF;
    RAISE EXCEPTION 'Call requires a deal and contact' USING ERRCODE='23514';
  END IF;
  -- Inserts serialize with deal closure. Updates already hold a task row lock;
  -- locking the deal there would reverse close's deal -> task lock order.
  IF TG_OP='INSERT' THEN
    SELECT * INTO v_deal FROM public.deals WHERE id=NEW.deal_id AND organization_id=NEW.organization_id FOR UPDATE;
  ELSE
    SELECT * INTO v_deal FROM public.deals WHERE id=NEW.deal_id AND organization_id=NEW.organization_id;
  END IF;
  IF NOT FOUND THEN RAISE EXCEPTION 'Call deal not found in organization' USING ERRCODE='23514'; END IF;
  IF NEW.status='pending' AND v_deal.closed_at IS NOT NULL THEN
    RAISE EXCEPTION 'A closed deal cannot have an open call' USING ERRCODE='23514';
  END IF;
  IF TG_OP='INSERT' OR NEW.contact_id IS DISTINCT FROM OLD.contact_id
    OR (NEW.status='pending' AND OLD.status IS DISTINCT FROM 'pending'::public.task_status) THEN
    SELECT * INTO v_contact FROM public.contacts WHERE id=NEW.contact_id AND organization_id=NEW.organization_id FOR SHARE;
    IF NOT FOUND OR length(regexp_replace(COALESCE(v_contact.phone,''),'[^0-9]','','g'))<7 THEN
      RAISE EXCEPTION 'A contact phone is required' USING ERRCODE='23514';
    END IF;
    IF COALESCE(v_contact.do_not_contact,false) OR v_contact.unsubscribed_at IS NOT NULL
      OR v_contact.automation_hold_at IS NOT NULL OR COALESCE(v_contact.open_to_work,false) THEN
      RAISE EXCEPTION 'Contact is suppressed for calls' USING ERRCODE='23514';
    END IF;
    IF v_deal.closed_at IS NOT NULL THEN RAISE EXCEPTION 'Deal is closed' USING ERRCODE='23514'; END IF;
  END IF;
  IF NULLIF(btrim(NEW.metadata->>'pitch'),'') IS NULL
    OR cardinality(regexp_split_to_array(btrim(NEW.metadata->>'pitch'), E'\\s+'))>60
    OR NEW.metadata->>'channel' IS DISTINCT FROM 'phone'
    OR NEW.metadata->>'source' IS NULL OR NEW.metadata->>'source' NOT IN ('manual','reply','deal') THEN
    RAISE EXCEPTION 'Call metadata requires phone channel, source and a pitch of at most 60 words' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_validate_crm_call_task ON public.tasks;
CREATE TRIGGER trg_validate_crm_call_task BEFORE INSERT OR UPDATE ON public.tasks
FOR EACH ROW EXECUTE FUNCTION public.validate_crm_call_task();

CREATE OR REPLACE FUNCTION public.cancel_crm_deal_tasks_on_close()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.closed_at IS NOT NULL AND OLD.closed_at IS NULL THEN
    UPDATE public.tasks
    SET status = 'cancelled'::public.task_status,
        updated_at = NOW(),
        metadata = COALESCE(metadata, '{}'::JSONB) || JSONB_BUILD_OBJECT(
          'cancelled_reason', 'deal_closed',
          'deal_stage', NEW.stage
        )
    WHERE deal_id = NEW.id
      AND organization_id = NEW.organization_id
      AND task_type IN (
        'nurture_reminder'::public.task_type,
        'linkedin_connect'::public.task_type,
        'manual_outreach'::public.task_type,
        'call'::public.task_type
      )
      AND status IN (
        'pending'::public.task_status,
        'in_progress'::public.task_status,
        'scheduled'::public.task_status,
        'in_review'::public.task_status
      );
  END IF;
  RETURN NEW;
END;
$$;


CREATE OR REPLACE FUNCTION public.create_crm_call_task(p_organization_id text,p_deal_id uuid,p_contact_id uuid,p_actor_user_id text,p_due_date timestamptz,p_note text,p_pitch text,p_metadata jsonb,p_source text DEFAULT 'manual')
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v_deal public.deals; v_contact public.contacts; v_note_id uuid; v_task public.tasks;
BEGIN
  IF NULLIF(btrim(p_note),'') IS NULL OR length(btrim(p_note))>5000
    OR NULLIF(btrim(p_pitch),'') IS NULL OR cardinality(regexp_split_to_array(btrim(p_pitch), E'\\s+'))>60
    OR p_source IS NULL OR p_source NOT IN ('manual','reply','deal') OR p_due_date IS NULL
    OR (p_metadata IS NOT NULL AND jsonb_typeof(p_metadata)<>'object') THEN
    RAISE EXCEPTION 'Call requires a note (1-5000 characters), pitch (1-60 words), source, due date and object metadata' USING ERRCODE='22023';
  END IF;
  SELECT * INTO v_deal FROM public.deals WHERE id=p_deal_id AND organization_id=p_organization_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Deal not found' USING ERRCODE='P0002'; END IF;
  IF v_deal.closed_at IS NOT NULL THEN RAISE EXCEPTION 'Deal is closed' USING ERRCODE='23514'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.user_organizations WHERE organization_id=p_organization_id AND user_id=p_actor_user_id)
    OR NOT EXISTS(SELECT 1 FROM public.user_organizations WHERE organization_id=p_organization_id AND user_id=v_deal.owner_user_id) THEN
    RAISE EXCEPTION 'Call actor and deal owner must be organization members' USING ERRCODE='23514';
  END IF;
  SELECT * INTO v_contact FROM public.contacts WHERE id=p_contact_id AND organization_id=p_organization_id FOR SHARE;
  IF NOT FOUND OR NOT EXISTS(SELECT 1 FROM public.company_contacts WHERE organization_id=p_organization_id AND company_id=v_deal.company_id AND contact_id=p_contact_id) THEN
    RAISE EXCEPTION 'Call contact is not linked to the deal company' USING ERRCODE='23514';
  END IF;
  IF EXISTS(SELECT 1 FROM public.tasks WHERE deal_id=p_deal_id AND task_type='call' AND status IN ('pending','in_progress','scheduled','in_review')) THEN
    RAISE EXCEPTION 'An open call already exists for this deal' USING ERRCODE='23505';
  END IF;
  INSERT INTO public.contact_notes(organization_id,contact_id,user_id,content,note_type,is_pinned)
  VALUES(p_organization_id,p_contact_id,p_actor_user_id,btrim(p_note),'call',false) RETURNING id INTO v_note_id;
  INSERT INTO public.deal_activities(deal_id,organization_id,activity_type,actor,actor_user_id,contact_id,title,metadata,bumps_last_activity)
  VALUES(p_deal_id,p_organization_id,'note',CASE WHEN p_source='manual' THEN 'user' ELSE 'system' END,p_actor_user_id,p_contact_id,'Call source note',jsonb_build_object('content',btrim(p_note),'contact_note_id',v_note_id,'source',p_source),p_source='manual');
  INSERT INTO public.tasks(organization_id,deal_id,company_id,contact_id,campaign_id,created_by_user_id,assigned_to_user_id,task_type,status,priority,title,description,due_date,body,pre_generated_copy,metadata)
  VALUES(p_organization_id,p_deal_id,v_deal.company_id,p_contact_id,v_deal.source_campaign_id,p_actor_user_id,v_deal.owner_user_id,'call','pending','high','Call '||COALESCE(NULLIF(v_contact.name,''),'contact'),btrim(p_note),p_due_date,btrim(p_pitch),btrim(p_pitch),
    COALESCE(p_metadata,'{}'::jsonb)||jsonb_build_object('channel','phone','source',p_source,'note_id',v_note_id,'note_to_ai',btrim(p_note),'pitch',btrim(p_pitch),'phone',btrim(v_contact.phone)))
  RETURNING * INTO v_task;
  RETURN to_jsonb(v_task);
END $$;

CREATE OR REPLACE FUNCTION public.snooze_crm_call_task(p_organization_id text,p_task_id uuid,p_actor_user_id text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v_task public.tasks; v_deal_id uuid;
BEGIN
  IF NOT EXISTS(SELECT 1 FROM public.user_organizations WHERE organization_id=p_organization_id AND user_id=p_actor_user_id) THEN
    RAISE EXCEPTION 'Call actor is not an organization member' USING ERRCODE='23514';
  END IF;
  SELECT deal_id INTO v_deal_id FROM public.tasks WHERE id=p_task_id AND organization_id=p_organization_id AND task_type='call';
  IF NOT FOUND THEN RAISE EXCEPTION 'Call task not found' USING ERRCODE='P0002'; END IF;
  -- Same lock order as create/close: deal then task avoids close/snooze deadlocks.
  PERFORM 1 FROM public.deals WHERE id=v_deal_id AND organization_id=p_organization_id FOR UPDATE;
  SELECT * INTO v_task FROM public.tasks WHERE id=p_task_id AND organization_id=p_organization_id AND task_type='call' FOR UPDATE;
  IF v_task.status IS DISTINCT FROM 'pending'::public.task_status THEN RAISE EXCEPTION 'Only pending calls can be snoozed' USING ERRCODE='23514'; END IF;
  UPDATE public.tasks SET due_date=GREATEST(COALESCE(due_date,now()),now())+interval '1 day',updated_at=now(),
    metadata=COALESCE(metadata,'{}'::jsonb)||jsonb_build_object('snoozed_at',now(),'snoozed_by_user_id',p_actor_user_id)
  WHERE id=p_task_id RETURNING * INTO v_task;
  RETURN to_jsonb(v_task);
END $$;

REVOKE ALL ON FUNCTION public.create_crm_call_task(text,uuid,uuid,text,timestamptz,text,text,jsonb,text) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.snooze_crm_call_task(text,uuid,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.create_crm_call_task(text,uuid,uuid,text,timestamptz,text,text,jsonb,text) TO service_role;
GRANT EXECUTE ON FUNCTION public.snooze_crm_call_task(text,uuid,text) TO service_role;

-- Preserve existing deletion cleanup and include call tasks.
CREATE OR REPLACE FUNCTION public.delete_crm_deal(
  p_organization_id TEXT,
  p_deal_id UUID,
  p_actor_user_id TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_deleted_id UUID;
BEGIN
  IF NULLIF(BTRIM(p_organization_id), '') IS NULL OR p_deal_id IS NULL THEN
    RAISE EXCEPTION 'Organization and deal are required' USING ERRCODE = '22023';
  END IF;

  PERFORM 1 FROM public.deals WHERE id=p_deal_id AND organization_id=p_organization_id FOR UPDATE;

  UPDATE public.tasks
  SET status = 'cancelled'::public.task_status,
      updated_at = NOW(),
      metadata = COALESCE(metadata, '{}'::JSONB) || JSONB_BUILD_OBJECT(
        'cancelled_reason', 'deal_deleted',
        'cancelled_by_user_id', p_actor_user_id,
        'cancelled_at', NOW()
      )
  WHERE organization_id = p_organization_id
    AND deal_id = p_deal_id
    AND task_type IN (
      'nurture_reminder'::public.task_type,
      'linkedin_connect'::public.task_type,
      'manual_outreach'::public.task_type,
      'call'::public.task_type
    )
    AND status IN (
      'pending'::public.task_status,
      'in_progress'::public.task_status,
      'scheduled'::public.task_status,
      'in_review'::public.task_status
    );

  DELETE FROM public.deals
  WHERE id = p_deal_id
    AND organization_id = p_organization_id
  RETURNING id INTO v_deleted_id;

  RETURN v_deleted_id IS NOT NULL;
END;
$$;

REVOKE ALL ON FUNCTION public.delete_crm_deal(TEXT, UUID, TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.delete_crm_deal(TEXT, UUID, TEXT)
  TO service_role;
