-- ============================================================
-- Migration: 417_crm-add-contact-task-workflows
-- Date:      2026-11-02
-- Purpose:   CRM quiet deals, section 12: the "Add a person" task (add_contact, 416) in the deal task workflows.
--            1. cancel_crm_deal_tasks_on_close: closing a deal also cancels its open add_contact task. Body of
--               next-release/376 with one type added.
--            2. audit_crm_deal_task: completing an add_contact task still writes "Deal task completed" but does not
--               move deals.last_activity_at. Adding a person is the owner's own work, not a customer touch; before,
--               every completed deal task counted as activity, so the deal would have waited 14 more days for its
--               first follow-up. Body of release_1.3.0/352 with that one value changed.
-- Projects:  selltonai-database/supabase (owner); selltonai-modal and selltonai read the rows.
-- Contract:  Both functions keep their names, signatures, triggers and grants (CREATE OR REPLACE). No data change.
-- Depends:   416, next-release/376, release_1.3.0/352.
-- Rollback:  rollback/417_crm-add-contact-task-workflows.rollback.sql
-- ============================================================

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
        'call'::public.task_type,
        'add_contact'::public.task_type
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
      -- 417: an "Add a person" task done is not a customer touch, so the deal stays quiet and its first
      -- follow-up comes at once (PLAN_CRM_QUIET_DEALS_TASKS section 12).
      NEW.task_type IS DISTINCT FROM 'add_contact'::public.task_type,
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

