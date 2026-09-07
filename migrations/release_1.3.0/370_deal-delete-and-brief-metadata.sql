-- KAN-282: complete manual-copy metadata, deal deletion, and sales-brief lifecycle.

ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS sales_brief_generated_at TIMESTAMPTZ;

DROP FUNCTION IF EXISTS public.finish_crm_manual_outreach_copy(TEXT, UUID, TEXT, TEXT, TEXT, JSONB);

CREATE OR REPLACE FUNCTION public.finish_crm_manual_outreach_copy(
  p_organization_id TEXT,
  p_task_id UUID,
  p_claim_token TEXT,
  p_subject TEXT,
  p_body TEXT,
  p_reasoning_note TEXT,
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
      reasoning_note = p_reasoning_note,
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

REVOKE ALL ON FUNCTION public.finish_crm_manual_outreach_copy(TEXT, UUID, TEXT, TEXT, TEXT, TEXT, JSONB)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.finish_crm_manual_outreach_copy(TEXT, UUID, TEXT, TEXT, TEXT, TEXT, JSONB)
  TO service_role;

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
      'manual_outreach'::public.task_type
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
