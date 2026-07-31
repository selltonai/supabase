-- ============================================================
-- Migration: 347_crm-deal-task-workflows
-- Date:      2026-07-17
-- Purpose:   Link tasks to deals and add idempotent CRM activity projection.
-- Projects:  selltonai-database/supabase (owner), selltonai-modal and
--            selltonai (writers/readers), backoffice (generic task reader).
-- Contract:  Additive. Requires 346 to be committed first.
-- ============================================================

ALTER TABLE public.tasks
  ADD COLUMN IF NOT EXISTS deal_id UUID;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.tasks'::REGCLASS
      AND conname = 'tasks_deal_id_fkey'
      AND confdeltype <> 'n'
  ) THEN
    ALTER TABLE public.tasks DROP CONSTRAINT tasks_deal_id_fkey;
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'public.tasks'::REGCLASS
      AND conname = 'tasks_deal_id_fkey'
  ) THEN
    ALTER TABLE public.tasks
      ADD CONSTRAINT tasks_deal_id_fkey
      FOREIGN KEY (deal_id) REFERENCES public.deals(id) ON DELETE SET NULL;
  END IF;
END
$$;

CREATE INDEX IF NOT EXISTS idx_tasks_deal_created
  ON public.tasks (deal_id, created_at DESC)
  WHERE deal_id IS NOT NULL;

DROP INDEX IF EXISTS public.idx_tasks_one_open_deal_nurture;
CREATE UNIQUE INDEX idx_tasks_one_open_deal_nurture
  ON public.tasks (deal_id)
  WHERE deal_id IS NOT NULL
    AND task_type IN ('nurture_reminder'::public.task_type, 'linkedin_connect'::public.task_type)
    AND status IN (
      'pending'::public.task_status,
      'in_progress'::public.task_status,
      'scheduled'::public.task_status,
      'in_review'::public.task_status
    );

DROP INDEX IF EXISTS public.idx_tasks_one_linkedin_connect_per_deal;
CREATE UNIQUE INDEX idx_tasks_one_linkedin_connect_per_deal
  ON public.tasks (deal_id)
  WHERE deal_id IS NOT NULL
    AND task_type = 'linkedin_connect'::public.task_type;

ALTER TABLE public.deal_activities
  ADD COLUMN IF NOT EXISTS source_event_key TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS idx_deal_activities_org_source_event
  ON public.deal_activities (organization_id, source_event_key)
  WHERE source_event_key IS NOT NULL;

ALTER TABLE public.deal_activities
  DROP CONSTRAINT IF EXISTS deal_activities_type_check;

ALTER TABLE public.deal_activities
  ADD CONSTRAINT deal_activities_type_check CHECK (
    activity_type IN (
      'deal_created',
      'stage_change',
      'amount_change',
      'owner_change',
      'nurture_change',
      'note',
      'email_in',
      'email_out',
      'linkedin_in',
      'linkedin_out',
      'task_created',
      'task_completed'
    )
  );

CREATE OR REPLACE FUNCTION public.validate_crm_deal_task_scope()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_deal public.deals;
BEGIN
  IF NEW.deal_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT *
  INTO v_deal
  FROM public.deals
  WHERE id = NEW.deal_id;

  IF NOT FOUND OR v_deal.organization_id <> NEW.organization_id THEN
    RAISE EXCEPTION 'Task deal does not belong to organization %', NEW.organization_id
      USING ERRCODE = '23514';
  END IF;

  IF NEW.company_id IS NULL THEN
    NEW.company_id := v_deal.company_id;
  ELSIF NEW.company_id <> v_deal.company_id THEN
    RAISE EXCEPTION 'Task company does not match deal company'
      USING ERRCODE = '23514';
  END IF;

  IF NEW.contact_id IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM public.company_contacts cc
    WHERE cc.organization_id = NEW.organization_id
      AND cc.company_id = v_deal.company_id
      AND cc.contact_id = NEW.contact_id
  ) THEN
    RAISE EXCEPTION 'Task contact is not linked to the deal company'
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_crm_deal_task_scope ON public.tasks;
CREATE TRIGGER trg_validate_crm_deal_task_scope
  BEFORE INSERT OR UPDATE OF deal_id, organization_id, company_id, contact_id
  ON public.tasks
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_crm_deal_task_scope();

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

DROP TRIGGER IF EXISTS trg_audit_crm_deal_task ON public.tasks;
CREATE TRIGGER trg_audit_crm_deal_task
  AFTER INSERT OR UPDATE OF status ON public.tasks
  FOR EACH ROW
  EXECUTE FUNCTION public.audit_crm_deal_task();

-- The legacy assignment trigger defaulted NULL on every UPDATE, which made an
-- explicit deal-owner unassignment impossible. Defaults belong to INSERT only.
CREATE OR REPLACE FUNCTION public.sync_tasks_assigned_to_user_id()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'INSERT' AND NEW.assigned_to_user_id IS NULL THEN
    NEW.assigned_to_user_id := NEW.created_by_user_id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_crm_deal_owner_tasks()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.owner_user_id IS DISTINCT FROM OLD.owner_user_id THEN
    UPDATE public.tasks
    SET assigned_to_user_id = NEW.owner_user_id,
        updated_at = NOW()
    WHERE deal_id = NEW.id
      AND organization_id = NEW.organization_id
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

DROP TRIGGER IF EXISTS trg_sync_crm_deal_owner_tasks ON public.deals;
CREATE TRIGGER trg_sync_crm_deal_owner_tasks
  AFTER UPDATE OF owner_user_id ON public.deals
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_crm_deal_owner_tasks();

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
        'manual_outreach'::public.task_type
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

DROP TRIGGER IF EXISTS trg_cancel_crm_deal_tasks_on_close ON public.deals;
CREATE TRIGGER trg_cancel_crm_deal_tasks_on_close
  AFTER UPDATE OF closed_at ON public.deals
  FOR EACH ROW
  EXECUTE FUNCTION public.cancel_crm_deal_tasks_on_close();

CREATE OR REPLACE FUNCTION public.record_crm_deal_activity_for_contact(
  p_organization_id TEXT,
  p_contact_id UUID,
  p_activity_type TEXT,
  p_title TEXT,
  p_source_event_key TEXT,
  p_metadata JSONB DEFAULT '{}'::JSONB,
  p_occurred_at TIMESTAMPTZ DEFAULT NOW(),
  p_actor TEXT DEFAULT 'system',
  p_actor_user_id TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_deal_id UUID;
  v_activity_id UUID;
  v_bumps_last_activity BOOLEAN;
BEGIN
  IF p_activity_type NOT IN ('email_in', 'email_out', 'linkedin_in', 'linkedin_out') THEN
    RAISE EXCEPTION 'Unsupported projected activity type: %', p_activity_type
      USING ERRCODE = '22023';
  END IF;

  IF p_actor NOT IN ('system', 'user') THEN
    RAISE EXCEPTION 'Unsupported activity actor: %', p_actor
      USING ERRCODE = '22023';
  END IF;

  IF NULLIF(BTRIM(p_source_event_key), '') IS NULL THEN
    RAISE EXCEPTION 'A stable source event key is required'
      USING ERRCODE = '22023';
  END IF;

  SELECT d.id
  INTO v_deal_id
  FROM public.deals d
  JOIN public.company_contacts cc
    ON cc.company_id = d.company_id
   AND cc.organization_id = d.organization_id
  WHERE d.organization_id = p_organization_id
    AND d.closed_at IS NULL
    AND cc.contact_id = p_contact_id
  ORDER BY (d.primary_contact_id = p_contact_id) DESC, d.stage_updated_at DESC, d.id
  LIMIT 1;

  IF v_deal_id IS NULL THEN
    RETURN NULL;
  END IF;

  v_bumps_last_activity := TRUE;

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
    v_deal_id,
    p_organization_id,
    p_activity_type,
    p_actor,
    CASE WHEN p_actor = 'user' THEN p_actor_user_id ELSE NULL END,
    p_contact_id,
    COALESCE(NULLIF(BTRIM(p_title), ''), 'Deal activity'),
    COALESCE(p_metadata, '{}'::JSONB),
    v_bumps_last_activity,
    BTRIM(p_source_event_key),
    COALESCE(p_occurred_at, NOW())
  )
  ON CONFLICT (organization_id, source_event_key)
    WHERE source_event_key IS NOT NULL
    DO NOTHING
  RETURNING id INTO v_activity_id;

  IF v_activity_id IS NULL THEN
    SELECT id
    INTO v_activity_id
    FROM public.deal_activities
    WHERE organization_id = p_organization_id
      AND source_event_key = BTRIM(p_source_event_key);

    IF NOT EXISTS (
      SELECT 1
      FROM public.deal_activities da
      WHERE da.id = v_activity_id
        AND da.deal_id = v_deal_id
        AND da.contact_id = p_contact_id
        AND da.activity_type = p_activity_type
    ) THEN
      RAISE EXCEPTION 'Source event key already belongs to a different CRM activity envelope'
        USING ERRCODE = '23505';
    END IF;
  END IF;

  RETURN v_activity_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.claim_due_crm_manual_outreach_tasks(
  p_organization_id TEXT,
  p_due_at TIMESTAMPTZ,
  p_limit INTEGER,
  p_claim_token TEXT
)
RETURNS SETOF public.tasks
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NULLIF(BTRIM(p_claim_token), '') IS NULL THEN
    RAISE EXCEPTION 'A manual-copy claim token is required' USING ERRCODE = '22023';
  END IF;

  RETURN QUERY
  WITH candidates AS (
    SELECT t.id
    FROM public.tasks t
    WHERE (p_organization_id IS NULL OR t.organization_id = p_organization_id)
      AND t.task_type = 'manual_outreach'::public.task_type
      AND t.status = 'pending'::public.task_status
      AND t.due_date <= p_due_at
      AND NULLIF(BTRIM(COALESCE(t.body, '')), '') IS NULL
      AND (
        NULLIF(t.metadata->>'copy_claimed_at', '') IS NULL
        OR (t.metadata->>'copy_claimed_at')::TIMESTAMPTZ < NOW() - INTERVAL '15 minutes'
      )
    ORDER BY t.due_date, t.created_at, t.id
    FOR UPDATE SKIP LOCKED
    LIMIT LEAST(GREATEST(COALESCE(p_limit, 1), 1), 500)
  )
  UPDATE public.tasks t
  SET metadata = COALESCE(t.metadata, '{}'::JSONB) || JSONB_BUILD_OBJECT(
        'copy_claim_token', BTRIM(p_claim_token),
        'copy_claimed_at', NOW()
      ),
      updated_at = NOW()
  FROM candidates c
  WHERE t.id = c.id
  RETURNING t.*;
END;
$$;

CREATE OR REPLACE FUNCTION public.finish_crm_manual_outreach_copy(
  p_organization_id TEXT,
  p_task_id UUID,
  p_claim_token TEXT,
  p_subject TEXT,
  p_body TEXT,
  p_metadata JSONB
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_row_count INTEGER;
BEGIN
  UPDATE public.tasks t
  SET subject = p_subject,
      body = p_body,
      pre_generated_copy = p_body,
      metadata = (COALESCE(p_metadata, t.metadata, '{}'::JSONB) - 'copy_claim_token' - 'copy_claimed_at'),
      updated_at = NOW()
  WHERE t.id = p_task_id
    AND t.organization_id = p_organization_id
    AND t.task_type = 'manual_outreach'::public.task_type
    AND t.status = 'pending'::public.task_status
    AND t.metadata->>'copy_claim_token' = BTRIM(p_claim_token)
    AND NULLIF(BTRIM(COALESCE(t.body, '')), '') IS NULL;

  GET DIAGNOSTICS v_row_count = ROW_COUNT;
  RETURN v_row_count > 0;
END;
$$;

CREATE OR REPLACE FUNCTION public.release_crm_manual_outreach_claim(
  p_organization_id TEXT,
  p_task_id UUID,
  p_claim_token TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_row_count INTEGER;
BEGIN
  UPDATE public.tasks t
  SET metadata = COALESCE(t.metadata, '{}'::JSONB) - 'copy_claim_token' - 'copy_claimed_at',
      updated_at = NOW()
  WHERE t.id = p_task_id
    AND t.organization_id = p_organization_id
    AND t.metadata->>'copy_claim_token' = BTRIM(p_claim_token);

  GET DIAGNOSTICS v_row_count = ROW_COUNT;
  RETURN v_row_count > 0;
END;
$$;

REVOKE ALL ON FUNCTION public.record_crm_deal_activity_for_contact(TEXT, UUID, TEXT, TEXT, TEXT, JSONB, TIMESTAMPTZ, TEXT, TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_crm_deal_activity_for_contact(TEXT, UUID, TEXT, TEXT, TEXT, JSONB, TIMESTAMPTZ, TEXT, TEXT)
  TO service_role;

REVOKE ALL ON FUNCTION public.claim_due_crm_manual_outreach_tasks(TEXT, TIMESTAMPTZ, INTEGER, TEXT)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.finish_crm_manual_outreach_copy(TEXT, UUID, TEXT, TEXT, TEXT, JSONB)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.release_crm_manual_outreach_claim(TEXT, UUID, TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_due_crm_manual_outreach_tasks(TEXT, TIMESTAMPTZ, INTEGER, TEXT)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.finish_crm_manual_outreach_copy(TEXT, UUID, TEXT, TEXT, TEXT, JSONB)
  TO service_role;
GRANT EXECUTE ON FUNCTION public.release_crm_manual_outreach_claim(TEXT, UUID, TEXT)
  TO service_role;

COMMENT ON COLUMN public.tasks.deal_id IS
  'Optional CRM deal linkage. Deal-scoped workflows are validated against organization/company/contact ownership.';

COMMENT ON COLUMN public.deal_activities.source_event_key IS
  'Stable producer event key used to make email, LinkedIn, and task activity projection idempotent.';

COMMENT ON FUNCTION public.record_crm_deal_activity_for_contact(TEXT, UUID, TEXT, TEXT, TEXT, JSONB, TIMESTAMPTZ, TEXT, TEXT) IS
  'Service-role-only idempotent projection of a real email/LinkedIn touch into the contact company open deal.';

-- Verify after apply:
-- SELECT column_name FROM information_schema.columns
-- WHERE table_name = 'tasks' AND column_name = 'deal_id';
-- SELECT indexname FROM pg_indexes
-- WHERE tablename IN ('tasks', 'deal_activities') AND indexname LIKE '%deal%';
