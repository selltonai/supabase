-- ============================================================
-- Migration: 350_crm-pipeline-v2-snooze-controls
-- Date:      2026-07-22
-- Purpose:   Add safe deal snoozing and a default-off organization automation gate.
-- Projects:  selltonai-database/supabase (owner), selltonai (BFF/UI),
--            selltonai-modal (nurture eligibility consumer).
-- Contract:  Additive after deployed CRM migrations 344-349. Browser access
--            remains service-role-only and automation remains disabled by default.
-- ============================================================

ALTER TABLE public.deals
  ADD COLUMN IF NOT EXISTS snoozed_until TIMESTAMPTZ;

ALTER TABLE public.organization_settings
  ADD COLUMN IF NOT EXISTS crm_automation_enabled BOOLEAN NOT NULL DEFAULT FALSE;

CREATE INDEX IF NOT EXISTS idx_deals_org_snoozed_open
  ON public.deals (organization_id, snoozed_until)
  WHERE closed_at IS NULL AND snoozed_until IS NOT NULL;

ALTER TABLE public.deal_activities
  DROP CONSTRAINT IF EXISTS deal_activities_type_check_v2_next;

ALTER TABLE public.deal_activities
  ADD CONSTRAINT deal_activities_type_check_v2_next CHECK (
    activity_type IN (
      'deal_created',
      'stage_change',
      'amount_change',
      'owner_change',
      'nurture_change',
      'snooze_change',
      'note',
      'email_in',
      'email_out',
      'linkedin_in',
      'linkedin_out',
      'task_created',
      'task_completed'
    )
  ) NOT VALID;

ALTER TABLE public.deal_activities
  VALIDATE CONSTRAINT deal_activities_type_check_v2_next;

ALTER TABLE public.deal_activities
  DROP CONSTRAINT IF EXISTS deal_activities_type_check;

ALTER TABLE public.deal_activities
  RENAME CONSTRAINT deal_activities_type_check_v2_next TO deal_activities_type_check;

CREATE OR REPLACE FUNCTION public.audit_crm_deal_snooze_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_actor TEXT := COALESCE(NULLIF(current_setting('app.crm_actor', TRUE), ''), 'system');
  v_actor_user_id TEXT := NULLIF(current_setting('app.crm_actor_user_id', TRUE), '');
BEGIN
  IF NEW.snoozed_until IS NOT DISTINCT FROM OLD.snoozed_until THEN
    RETURN NEW;
  END IF;

  IF v_actor NOT IN ('system', 'user') THEN
    v_actor := 'system';
    v_actor_user_id := NULL;
  END IF;

  INSERT INTO public.deal_activities (
    deal_id,
    organization_id,
    activity_type,
    actor,
    actor_user_id,
    title,
    metadata,
    bumps_last_activity
  ) VALUES (
    NEW.id,
    NEW.organization_id,
    'snooze_change',
    v_actor,
    v_actor_user_id,
    CASE WHEN NEW.snoozed_until IS NULL THEN 'Deal snooze cleared' ELSE 'Deal snoozed' END,
    JSONB_BUILD_OBJECT('from', OLD.snoozed_until, 'to', NEW.snoozed_until),
    FALSE
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_audit_crm_deal_snooze_change ON public.deals;
CREATE TRIGGER trg_audit_crm_deal_snooze_change
  AFTER UPDATE OF snoozed_until ON public.deals
  FOR EACH ROW
  EXECUTE FUNCTION public.audit_crm_deal_snooze_change();

CREATE OR REPLACE FUNCTION public.set_crm_deal_snooze(
  p_deal_id UUID,
  p_organization_id TEXT,
  p_actor_user_id TEXT,
  p_snoozed_until TIMESTAMPTZ
)
RETURNS public.deals
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_deal public.deals;
BEGIN
  IF p_actor_user_id IS NULL OR NOT EXISTS (
    SELECT 1
    FROM public.user_organizations uo
    WHERE uo.organization_id = p_organization_id
      AND uo.user_id = p_actor_user_id
  ) THEN
    RAISE EXCEPTION 'Deal actor is not an organization member'
      USING ERRCODE = '23514';
  END IF;

  PERFORM set_config('app.crm_actor', 'user', TRUE);
  PERFORM set_config('app.crm_actor_user_id', p_actor_user_id, TRUE);
  PERFORM set_config('app.crm_contact_id', '', TRUE);

  UPDATE public.deals
  SET snoozed_until = p_snoozed_until
  WHERE id = p_deal_id
    AND organization_id = p_organization_id
  RETURNING * INTO v_deal;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Deal not found'
      USING ERRCODE = 'P0002';
  END IF;

  RETURN v_deal;
END;
$$;

REVOKE ALL ON FUNCTION public.set_crm_deal_snooze(UUID, TEXT, TEXT, TIMESTAMPTZ)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.set_crm_deal_snooze(UUID, TEXT, TEXT, TIMESTAMPTZ)
  TO service_role;

COMMENT ON COLUMN public.deals.snoozed_until IS
  'When in the future, automated CRM task generation skips this deal. NULL means not snoozed.';
COMMENT ON COLUMN public.organization_settings.crm_automation_enabled IS
  'Per-organization CRM automation gate. Defaults false and is independent from UI visibility and notification rollout.';
COMMENT ON FUNCTION public.set_crm_deal_snooze(UUID, TEXT, TEXT, TIMESTAMPTZ) IS
  'Service-role-only organization-scoped deal snooze update with membership validation and audit.';

-- Verify:
-- SELECT column_name, is_nullable, column_default
-- FROM information_schema.columns
-- WHERE table_schema = 'public'
--   AND ((table_name = 'deals' AND column_name = 'snoozed_until')
--     OR (table_name = 'organization_settings' AND column_name = 'crm_automation_enabled'));
-- SELECT indexname FROM pg_indexes WHERE indexname = 'idx_deals_org_snoozed_open';
-- SELECT to_regprocedure('public.set_crm_deal_snooze(uuid,text,text,timestamp with time zone)');
--
-- Rollback (application code must be rolled back first):
-- DROP TRIGGER IF EXISTS trg_audit_crm_deal_snooze_change ON public.deals;
-- DROP FUNCTION IF EXISTS public.audit_crm_deal_snooze_change();
-- DROP FUNCTION IF EXISTS public.set_crm_deal_snooze(UUID, TEXT, TEXT, TIMESTAMPTZ);
-- DROP INDEX IF EXISTS public.idx_deals_org_snoozed_open;
-- ALTER TABLE public.deals DROP COLUMN IF EXISTS snoozed_until;
-- ALTER TABLE public.organization_settings DROP COLUMN IF EXISTS crm_automation_enabled;
-- Recreate the pre-350 deal_activities_type_check before dropping snooze_change rows.
