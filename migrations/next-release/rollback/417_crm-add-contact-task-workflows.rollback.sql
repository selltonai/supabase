-- Reverses 417: both functions as 376 and 352 wrote them. The add_contact enum value (416) stays; an enum value
-- cannot be dropped.

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


CREATE OR REPLACE FUNCTION public.audit_crm_deal_task()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.deal_id IS NULL THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.deal_activities (
      deal_id,
      organization_id,
      activity_type,
      actor,
      actor_user_id,
      contact_id,
      title,
      metadata,
      bumps_last_activity,
      source_event_key,
      created_at
    ) VALUES (
      NEW.deal_id,
      NEW.organization_id,
      'task_created',
      CASE WHEN EXISTS (SELECT 1 FROM public."user" u WHERE u.id = NEW.created_by_user_id) THEN 'user' ELSE 'system' END,
      (SELECT u.id FROM public."user" u WHERE u.id = NEW.created_by_user_id LIMIT 1),
      NEW.contact_id,
      'Deal task created',
      JSONB_BUILD_OBJECT(
        'task_id', NEW.id,
        'task_type', NEW.task_type,
        'channel', NEW.metadata->>'channel',
        'due_date', NEW.due_date
      ),
      FALSE,
      'task_created:' || NEW.id::TEXT,
      NEW.created_at
    )
    ON CONFLICT (organization_id, source_event_key)
      WHERE source_event_key IS NOT NULL
      DO NOTHING;
  ELSIF NEW.status = 'completed'::public.task_status
    AND OLD.status IS DISTINCT FROM NEW.status THEN
    INSERT INTO public.deal_activities (
      deal_id,
      organization_id,
      activity_type,
      actor,
      actor_user_id,
      contact_id,
      title,
      metadata,
      bumps_last_activity,
      source_event_key,
      created_at
    ) VALUES (
      NEW.deal_id,
      NEW.organization_id,
      'task_completed',
      'user',
      (SELECT u.id FROM public."user" u WHERE u.id = NEW.completed_by_user_id LIMIT 1),
      NEW.contact_id,
      'Deal task completed',
      JSONB_BUILD_OBJECT('task_id', NEW.id, 'task_type', NEW.task_type, 'channel', NEW.metadata->>'channel'),
      TRUE,
      'task_completed:' || NEW.id::TEXT,
      LEAST(COALESCE(NEW.completed_at, NOW()), NOW())
    )
    ON CONFLICT (organization_id, source_event_key)
      WHERE source_event_key IS NOT NULL
      DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;

