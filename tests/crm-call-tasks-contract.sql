\set ON_ERROR_STOP on
BEGIN;
INSERT INTO public."user" VALUES ('owner'),('manager'),('outsider'),('replacement');
INSERT INTO public.user_organizations VALUES ('owner','org-a'),('manager','org-a'),('replacement','org-a'),('outsider','org-b');
INSERT INTO public.contacts(id,organization_id,name,phone,stop_drafts) VALUES ('20000000-0000-0000-0000-000000000001','org-a','Test Contact','+44 7000 123456',true);
INSERT INTO public.deals(id,organization_id,company_id,primary_contact_id,owner_user_id,stage) VALUES ('30000000-0000-0000-0000-000000000001','org-a','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','owner','LEAD');
INSERT INTO public.company_contacts VALUES ('org-a','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001');
DO $$
DECLARE v_task jsonb; v_id uuid; v_count integer; v_due timestamptz; v_field text;
BEGIN
  IF has_function_privilege('authenticated','public.create_crm_call_task(text,uuid,uuid,text,timestamptz,text,text,jsonb,text)','EXECUTE') OR NOT has_function_privilege('service_role','public.create_crm_call_task(text,uuid,uuid,text,timestamptz,text,text,jsonb,text)','EXECUTE') THEN RAISE EXCEPTION 'RPC privilege contract broken'; END IF;
  BEGIN
    PERFORM public.create_crm_call_task('org-a','30000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','outsider',now(),'Asked for pricing','Discuss requested pricing.', '{}');
    RAISE EXCEPTION 'Cross tenant actor accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    PERFORM public.create_crm_call_task('org-b','30000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','outsider',now(),'Asked for pricing','Discuss requested pricing.', '{}');
    RAISE EXCEPTION 'Cross tenant deal accepted';
  EXCEPTION WHEN no_data_found THEN NULL; END;
  UPDATE public.contacts SET phone=NULL;
  BEGIN
    PERFORM public.create_crm_call_task('org-a','30000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','owner',now(),'Asked for pricing','Discuss requested pricing.', '{}');
    RAISE EXCEPTION 'Missing phone accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;
  UPDATE public.contacts SET phone='+44 7000 123456', automation_hold_at=now();
  BEGIN
    PERFORM public.create_crm_call_task('org-a','30000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','owner',now(),'Asked for pricing','Discuss requested pricing.', '{}');
    RAISE EXCEPTION 'Held contact accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;
  UPDATE public.contacts SET automation_hold_at=NULL;
  FOREACH v_field IN ARRAY ARRAY['do_not_contact','open_to_work','unsubscribed_at','automation_hold_reason','ooo_until'] LOOP
    EXECUTE format('UPDATE public.contacts SET %I = %s',v_field,CASE WHEN v_field='unsubscribed_at' THEN 'now()' WHEN v_field='automation_hold_reason' THEN '''manual_hold''' WHEN v_field='ooo_until' THEN 'now()+interval ''1 day''' ELSE 'true' END);
    BEGIN
      PERFORM public.create_crm_call_task('org-a','30000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','owner',now(),'Asked for pricing','Discuss requested pricing.', '{}');
      RAISE EXCEPTION 'Suppressed contact accepted: %',v_field;
    EXCEPTION WHEN check_violation THEN NULL; END;
    EXECUTE format('UPDATE public.contacts SET %I = NULL',v_field);
  END LOOP;
  IF EXISTS(SELECT 1 FROM contact_notes) OR EXISTS(SELECT 1 FROM tasks) THEN RAISE EXCEPTION 'Rejected creation left partial rows'; END IF;
  BEGIN
    PERFORM public.create_crm_call_task('org-a','30000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','owner',now(),'Asked for pricing',repeat('word ',61), '{}');
    RAISE EXCEPTION 'Overlong pitch accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  v_task := public.create_crm_call_task('org-a','30000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','manager',now(),'Asked for pricing','Discuss requested pricing.', '{"phone":"spoof","source":"reply","channel":"email"}');
  v_id := (v_task->>'id')::uuid;
  IF v_task->>'assigned_to_user_id'<>'owner' OR v_task#>>'{metadata,phone}'<>'+44 7000 123456' OR v_task#>>'{metadata,source}'<>'manual' OR v_task#>>'{metadata,channel}'<>'phone' OR NOT EXISTS(SELECT 1 FROM contact_notes WHERE id=(v_task#>>'{metadata,note_id}')::uuid AND content='Asked for pricing') THEN RAISE EXCEPTION 'Atomic canonical payload broken'; END IF;
  SELECT count(*) INTO v_count FROM contact_notes;
  BEGIN
    PERFORM public.create_crm_call_task('org-a','30000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','owner',now(),'Other note','Other pitch.', '{}');
    RAISE EXCEPTION 'Duplicate call accepted';
  EXCEPTION WHEN unique_violation THEN NULL; END;
  IF (SELECT count(*) FROM contact_notes)<>v_count THEN RAISE EXCEPTION 'Duplicate leaked orphan note'; END IF;
  BEGIN
    UPDATE public.tasks SET status='approved' WHERE id=v_id;
    RAISE EXCEPTION 'Call approved for dispatch';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    UPDATE public.tasks SET send_status='sending' WHERE id=v_id;
    RAISE EXCEPTION 'Call sent through sender';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    UPDATE public.tasks SET task_type='manual_outreach' WHERE id=v_id;
    RAISE EXCEPTION 'Call converted into sender task';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    PERFORM public.snooze_crm_call_task('org-a',v_id,'outsider');
    RAISE EXCEPTION 'Cross tenant actor snoozed call';
  EXCEPTION WHEN check_violation THEN NULL; END;
  SELECT due_date INTO v_due FROM tasks WHERE id=v_id;
  v_task := public.snooze_crm_call_task('org-a',v_id,'manager');
  IF (v_task->>'due_date')::timestamptz <> v_due + interval '1 day' THEN RAISE EXCEPTION 'Snooze duration incorrect'; END IF;
  UPDATE public.deals SET owner_user_id='replacement';
  IF (SELECT assigned_to_user_id FROM tasks WHERE id=v_id)<>'replacement' THEN RAISE EXCEPTION 'Owner transfer missed call'; END IF;
  UPDATE public.tasks SET status='completed', completed_at=now(), completed_by_user_id='replacement' WHERE id=v_id;
  IF NOT EXISTS(SELECT 1 FROM deal_activities WHERE activity_type='task_completed' AND metadata->>'task_id'=v_id::text) THEN RAISE EXCEPTION 'Completion audit missing'; END IF;
  v_task := public.create_crm_call_task('org-a','30000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','replacement',now(),'Second requested call','Follow up on requested pricing.', '{}','deal');
  v_id := (v_task->>'id')::uuid;
  UPDATE public.deals SET stage='WON',closed_at=now();
  IF (SELECT status FROM tasks WHERE id=v_id)<>'cancelled' THEN RAISE EXCEPTION 'Close did not cancel call'; END IF;
  BEGIN
    UPDATE public.tasks SET status='pending' WHERE id=v_id;
    RAISE EXCEPTION 'Closed call reopened';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    PERFORM public.snooze_crm_call_task('org-a',v_id,'replacement');
    RAISE EXCEPTION 'Cancelled call snoozed';
  EXCEPTION WHEN check_violation THEN NULL; END;
  PERFORM public.delete_crm_deal('org-a','30000000-0000-0000-0000-000000000001','replacement');
  IF (SELECT deal_id FROM tasks WHERE id=v_id) IS NOT NULL THEN RAISE EXCEPTION 'Delete did not detach cancelled call'; END IF;
  DELETE FROM contacts WHERE id='20000000-0000-0000-0000-000000000001';
  IF EXISTS(SELECT 1 FROM tasks WHERE contact_id IS NOT NULL) THEN RAISE EXCEPTION 'Contact deletion blocked'; END IF;
END $$;
INSERT INTO notifications(type) VALUES('call_due'),('task_assigned'),('linkedin_campaign_account_missing');
ROLLBACK;
