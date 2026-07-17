-- ============================================================
-- Migration: 348_crm-deal-notifications
-- Date:      2026-07-17
-- Purpose:   Add deduplicated CRM deal lifecycle notifications.
-- Projects:  selltonai-database/supabase (owner), selltonai (reader/UI),
--            selltonai-modal (task notification producer).
-- Contract:  Replaces the notification type CHECK with the union of every
--            type verified on stage plus shipped LinkedIn and CRM types.
-- Depends:   344-347.
-- ============================================================

ALTER TABLE public.notifications
  DROP CONSTRAINT IF EXISTS notifications_type_check_crm_next;

ALTER TABLE public.notifications
  ADD CONSTRAINT notifications_type_check_crm_next CHECK (
    type IN (
      'task_assigned',
      'task_due',
      'contact_replied',
      'campaign_alert',
      'campaign_completed',
      'budget_warning',
      'budget_critical',
      'daily_briefing',
      'weekly_report',
      'approval_needed',
      'system_alert',
      'phone_discovery_complete',
      'phone_discovery_failed',
      'enrichment_complete',
      'research_complete',
      'deep_research_settings_changed',
      'linkedin_account_credentials_expired',
      'linkedin_account_restricted',
      'linkedin_invite_accepted',
      'linkedin_cap_reached',
      'linkedin_sequence_completed',
      'linkedin_sequence_paused_on_reply',
      'deal_created',
      'deal_stage_changed',
      'deal_owner_changed'
    )
  ) NOT VALID;

-- Validate the replacement while the existing constraint is still protecting
-- writes. A drift/type mismatch therefore fails without leaving the table
-- unconstrained.
ALTER TABLE public.notifications
  VALIDATE CONSTRAINT notifications_type_check_crm_next;

ALTER TABLE public.notifications
  DROP CONSTRAINT IF EXISTS notifications_type_check;

ALTER TABLE public.notifications
  RENAME CONSTRAINT notifications_type_check_crm_next TO notifications_type_check;

CREATE OR REPLACE FUNCTION public.notify_crm_deal_lifecycle()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_notifications_suppressed BOOLEAN := COALESCE(
    NULLIF(current_setting('app.crm_suppress_notifications', TRUE), '')::BOOLEAN,
    FALSE
  );
BEGIN
  IF v_notifications_suppressed THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' AND NEW.owner_user_id IS NOT NULL THEN
    INSERT INTO public.notifications (
      organization_id,
      user_id,
      type,
      title,
      body,
      action_url,
      entity_type,
      entity_id,
      metadata,
      channels,
      priority,
      dedup_key
    ) VALUES (
      NEW.organization_id,
      NEW.owner_user_id,
      'deal_created',
      'New deal: ' || NEW.name,
      'A deal entered the ' || REPLACE(INITCAP(LOWER(NEW.stage)), '_', ' ') || ' stage.',
      '/crm?tab=pipeline&dealId=' || NEW.id::TEXT,
      'deal',
      NEW.id::TEXT,
      JSONB_BUILD_OBJECT('deal_id', NEW.id, 'stage', NEW.stage),
      ARRAY['in_app']::TEXT[],
      'normal',
      'deal_created:' || NEW.id::TEXT
    )
    ON CONFLICT (user_id, dedup_key) WHERE dedup_key IS NOT NULL DO NOTHING;
    RETURN NEW;
  END IF;

  IF NEW.owner_user_id IS DISTINCT FROM OLD.owner_user_id
    AND NEW.owner_user_id IS NOT NULL THEN
    INSERT INTO public.notifications (
      organization_id,
      user_id,
      type,
      title,
      body,
      action_url,
      entity_type,
      entity_id,
      metadata,
      channels,
      priority,
      dedup_key
    ) VALUES (
      NEW.organization_id,
      NEW.owner_user_id,
      'deal_owner_changed',
      'Deal assigned: ' || NEW.name,
      'You are now responsible for this deal and its open tasks.',
      '/crm?tab=pipeline&dealId=' || NEW.id::TEXT,
      'deal',
      NEW.id::TEXT,
      JSONB_BUILD_OBJECT('deal_id', NEW.id, 'previous_owner_user_id', OLD.owner_user_id),
      ARRAY['in_app']::TEXT[],
      'normal',
      'deal_owner:' || NEW.id::TEXT || ':' || NEW.owner_user_id
    )
    ON CONFLICT (user_id, dedup_key) WHERE dedup_key IS NOT NULL DO NOTHING;
  END IF;

  IF NEW.stage IS DISTINCT FROM OLD.stage
    AND NEW.owner_user_id IS NOT NULL
    AND COALESCE(NULLIF(current_setting('app.crm_actor', TRUE), ''), 'system') = 'system' THEN
    INSERT INTO public.notifications (
      organization_id,
      user_id,
      type,
      title,
      body,
      action_url,
      entity_type,
      entity_id,
      metadata,
      channels,
      priority,
      dedup_key
    ) VALUES (
      NEW.organization_id,
      NEW.owner_user_id,
      'deal_stage_changed',
      'Deal advanced: ' || NEW.name,
      'The deal moved to ' || REPLACE(INITCAP(LOWER(NEW.stage)), '_', ' ') || '.',
      '/crm?tab=pipeline&dealId=' || NEW.id::TEXT,
      'deal',
      NEW.id::TEXT,
      JSONB_BUILD_OBJECT('deal_id', NEW.id, 'from_stage', OLD.stage, 'stage', NEW.stage),
      ARRAY['in_app']::TEXT[],
      'normal',
      'deal_stage:' || NEW.id::TEXT || ':' || NEW.stage
    )
    ON CONFLICT (user_id, dedup_key) WHERE dedup_key IS NOT NULL DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_crm_deal_lifecycle ON public.deals;
CREATE TRIGGER trg_notify_crm_deal_lifecycle
  AFTER INSERT OR UPDATE OF owner_user_id, stage ON public.deals
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_crm_deal_lifecycle();

COMMENT ON FUNCTION public.notify_crm_deal_lifecycle() IS
  'Creates in-app-only, deduplicated deal-created, automated-stage, and owner-transfer notifications. Reconciliation may suppress them with app.crm_suppress_notifications.';

-- Verify after apply:
-- SELECT pg_get_constraintdef(oid) FROM pg_constraint
-- WHERE conrelid = 'public.notifications'::REGCLASS
--   AND conname = 'notifications_type_check';
