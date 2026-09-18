-- KAN-305: repair call validation against the actual task_status enum.
-- Affected: selltonai and selltonai-modal call creation/lifecycle.
-- 376 is already applied and immutable. Stage task_status contains failed,
-- not rejected/approved. PL/pgSQL coerces every literal even on INSERT,
-- so the nonexistent rejected value prevented all call creation.
-- Preserve the full guard body; change only its terminal-state literals.
-- Prerequisite: migrations 375 and 376. Safe to reapply.

CREATE OR REPLACE FUNCTION public.validate_crm_call_task()
RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE v_deal public.deals; v_contact public.contacts;
BEGIN
  IF TG_OP='UPDATE' AND OLD.task_type='call'::public.task_type AND NEW.task_type IS DISTINCT FROM OLD.task_type THEN
    RAISE EXCEPTION 'A call cannot change to a sending task type' USING ERRCODE='23514';
  END IF;
  IF NEW.task_type IS DISTINCT FROM 'call'::public.task_type THEN RETURN NEW; END IF;
  IF TG_OP='UPDATE' AND OLD.status IN ('completed','cancelled','failed') AND NEW.status IS DISTINCT FROM OLD.status THEN
    RAISE EXCEPTION 'A finished call cannot be reopened' USING ERRCODE='23514';
  END IF;
  IF NEW.status IS NULL OR NEW.status NOT IN ('pending','completed','cancelled','failed')
    OR COALESCE(NEW.scheduled,false) OR COALESCE(NEW.send_status,'not_sent')<>'not_sent' THEN
    RAISE EXCEPTION 'Calls cannot be approved or dispatched' USING ERRCODE='23514';
  END IF;
  -- FK SET NULL is part of contact/deal deletion; retain cancelled history.
  IF NEW.deal_id IS NULL OR NEW.contact_id IS NULL THEN
    IF TG_OP='UPDATE' AND (NEW.deal_id IS NULL AND (OLD.deal_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.deals WHERE id=OLD.deal_id))
      OR NEW.contact_id IS NULL AND (OLD.contact_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.contacts WHERE id=OLD.contact_id))) THEN
      IF NEW.status NOT IN ('completed','cancelled','failed') THEN NEW.status := 'cancelled'; END IF;
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
      OR v_contact.automation_hold_at IS NOT NULL OR NULLIF(btrim(v_contact.automation_hold_reason),'') IS NOT NULL
      OR v_contact.ooo_until>now() OR COALESCE(v_contact.open_to_work,false) THEN
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
