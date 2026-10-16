-- Migration: 400_crm-list-delete-jobs-and-company-move
-- Ticket: KAN-334. Built as 394 on 2026-10-14; renumbered because stage holds 394-399.
-- KAN-334: CRM list delete as a background job, and moving a pending company review to another campaign.
-- Owner: selltonai-database/supabase. Consumers: selltonai-modal (delete job, preview, GET /lists delete_state)
-- and selltonai (POST /api/tasks/company-verification/move).
-- The code that calls it is live since 2026-10-15 00:32 (Modal production 60c73f5, in v355 and v356;
-- frontend main 608466ce) and fails without it. Old apps also work with it applied (nullable columns,
-- new functions).
--
-- 1. crm_lists.delete_state: NULL (normal), 'deleting', 'failed'.
-- 2. crm_list_delete_jobs: one row per delete attempt, progress for the UI. list_id has no foreign key
--    on purpose: the job row outlives the list it deleted.
-- 3. campaign_companies.moved_from_campaign_id / moved_at / moved_by: set by move_company_review.
-- 3b. crm_import_jobs.summary: what became of every imported row (saved, merged, linked, failed), for the import summary.
-- 4. crm_list_delete_batch(org, list, limit): deletes up to <limit> companies of the list (crm_list_id or a
--    raw record's extracted_company_id), their people that belong to no other company, and, once no company
--    is left, the list's people that belong to no company. One call = one transaction. Ends the LinkedIn
--    journeys and sequence actions of the deleted people (no foreign key covers them), rejects their open
--    reply drafts, cancels open tasks of the deleted companies and people. Cascades do the rest.
--    Returns counts; the job calls it until deleted_companies + deleted_contacts = 0.
-- 5. crm_list_delete_preview(org, list): the counts for the confirmation dialog.
-- 6. move_company_review(org, company, from, to, user): the only writer of a move. Returns {ok, code, ...}.
--
-- All three functions: SECURITY DEFINER, search_path pinned, revoked from PUBLIC/anon/authenticated,
-- service_role only (migration 390's rule), asserted at the end of this file.
--
-- Rollback: rollback/400-401_crm-list-delete-and-move.rollback.sql (to apply it, copy it to the next free
-- number in next-release/ and list it in the manifest: the ledger refuses a changed file).

SET LOCAL lock_timeout = '5s';

-- 1. List delete state ---------------------------------------------------------------------------

ALTER TABLE public.crm_lists
  ADD COLUMN IF NOT EXISTS delete_state text;

ALTER TABLE public.crm_lists
  DROP CONSTRAINT IF EXISTS crm_lists_delete_state_check;
ALTER TABLE public.crm_lists
  ADD CONSTRAINT crm_lists_delete_state_check
  CHECK (delete_state IS NULL OR delete_state IN ('deleting', 'failed'));

COMMENT ON COLUMN public.crm_lists.delete_state IS
  'KAN-334: NULL = normal; deleting = a delete job runs (hidden from pickers); failed = last delete job failed (retry continues).';

-- 2. Delete jobs ---------------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.crm_list_delete_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  list_id uuid NOT NULL,
  list_name text,
  status text NOT NULL DEFAULT 'queued'
    CHECK (status IN ('queued', 'deleting', 'completed', 'failed')),
  phase text NOT NULL DEFAULT 'queued'
    CHECK (phase IN ('queued', 'companies', 'raw_records', 'finalizing', 'completed', 'failed')),
  total_companies integer NOT NULL DEFAULT 0 CHECK (total_companies >= 0),
  total_contacts integer NOT NULL DEFAULT 0 CHECK (total_contacts >= 0),
  deleted_companies integer NOT NULL DEFAULT 0 CHECK (deleted_companies >= 0),
  deleted_contacts integer NOT NULL DEFAULT 0 CHECK (deleted_contacts >= 0),
  batch_size integer,
  batches integer NOT NULL DEFAULT 0 CHECK (batches >= 0),
  last_error text,
  started_at timestamptz,
  finished_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_crm_list_delete_jobs_one_open_per_list
  ON public.crm_list_delete_jobs (list_id)
  WHERE status IN ('queued', 'deleting');

CREATE INDEX IF NOT EXISTS idx_crm_list_delete_jobs_org_list_created
  ON public.crm_list_delete_jobs (organization_id, list_id, created_at DESC);

ALTER TABLE public.crm_list_delete_jobs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.crm_list_delete_jobs FROM anon, authenticated;
GRANT ALL ON TABLE public.crm_list_delete_jobs TO service_role;

COMMENT ON TABLE public.crm_list_delete_jobs IS
  'KAN-334: progress of a CRM list delete run by the Modal function delete_crm_list. Written by service_role only.';

-- 3. Move columns --------------------------------------------------------------------------------

ALTER TABLE public.campaign_companies
  ADD COLUMN IF NOT EXISTS moved_from_campaign_id uuid,
  ADD COLUMN IF NOT EXISTS moved_at timestamptz,
  ADD COLUMN IF NOT EXISTS moved_by text;

COMMENT ON COLUMN public.campaign_companies.moved_from_campaign_id IS
  'KAN-334: set when the company''s pending review was moved here from another campaign (move_company_review). V3 treats it like a seed: no market or hard-filter block.';

-- 3b. Import summary --------------------------------------------------------------------------

ALTER TABLE public.crm_import_jobs
  ADD COLUMN IF NOT EXISTS summary jsonb;

COMMENT ON COLUMN public.crm_import_jobs.summary IS
  'KAN-334: final counts of a CRM import (rows, companies_saved, companies_linked_existing, companies_merged, rows_extracted, rows_failed, rows_left_over). Written by Modal at completion.';

-- 4. Delete batch --------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.crm_list_delete_batch(
  p_organization_id text,
  p_list_id uuid,
  p_limit integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_companies uuid[] := '{}';
  v_contacts uuid[] := '{}';
  v_deleted_companies integer := 0;
  v_deleted_contacts integer := 0;
  v_journeys integer := 0;
  v_actions integer := 0;
  v_drafts integer := 0;
  v_tasks integer := 0;
BEGIN
  IF NULLIF(btrim(p_organization_id), '') IS NULL OR p_list_id IS NULL THEN
    RAISE EXCEPTION 'Organization and list are required' USING ERRCODE = '22023';
  END IF;
  IF p_limit IS NULL OR p_limit < 1 OR p_limit > 1000 THEN
    RAISE EXCEPTION 'Batch limit must be between 1 and 1000' USING ERRCODE = '22023';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.crm_lists WHERE id = p_list_id AND organization_id = p_organization_id
  ) THEN
    RETURN jsonb_build_object('list_found', false, 'deleted_companies', 0, 'deleted_contacts', 0);
  END IF;

  -- The list's companies: owned by it, or extracted from one of its rows.
  SELECT coalesce(array_agg(s.id), '{}')
  INTO v_companies
  FROM (
    SELECT u.id
    FROM (
      SELECT c.id
      FROM public.companies c
      WHERE c.organization_id = p_organization_id
        AND c.crm_list_id = p_list_id::text
      UNION
      SELECT r.extracted_company_id
      FROM public.crm_raw_records r
      WHERE r.list_id = p_list_id
        AND r.organization_id = p_organization_id
        AND r.extracted_company_id IS NOT NULL
    ) u
    JOIN public.companies c2 ON c2.id = u.id AND c2.organization_id = p_organization_id
    ORDER BY u.id
    LIMIT p_limit
  ) s;

  IF cardinality(v_companies) > 0 THEN
    -- People at these companies or extracted with them, who belong to no company outside this batch.
    SELECT coalesce(array_agg(DISTINCT p.contact_id), '{}')
    INTO v_contacts
    FROM (
      SELECT cc.contact_id
      FROM public.company_contacts cc
      WHERE cc.organization_id = p_organization_id
        AND cc.company_id = ANY (v_companies)
      UNION
      SELECT r.extracted_person_id
      FROM public.crm_raw_records r
      WHERE r.list_id = p_list_id
        AND r.organization_id = p_organization_id
        AND r.extracted_person_id IS NOT NULL
        AND r.extracted_company_id = ANY (v_companies)
    ) p
    WHERE NOT EXISTS (
      SELECT 1
      FROM public.company_contacts other
      WHERE other.contact_id = p.contact_id
        AND NOT (other.company_id = ANY (v_companies))
    );
  ELSE
    -- No company left: the list's people that belong to no company.
    SELECT coalesce(array_agg(s.contact_id), '{}')
    INTO v_contacts
    FROM (
      SELECT DISTINCT r.extracted_person_id AS contact_id
      FROM public.crm_raw_records r
      WHERE r.list_id = p_list_id
        AND r.organization_id = p_organization_id
        AND r.extracted_person_id IS NOT NULL
        AND NOT EXISTS (
          SELECT 1 FROM public.company_contacts cc WHERE cc.contact_id = r.extracted_person_id
        )
      ORDER BY 1
      LIMIT p_limit
    ) s;
  END IF;

  IF cardinality(v_companies) = 0 AND cardinality(v_contacts) = 0 THEN
    RETURN jsonb_build_object('list_found', true, 'deleted_companies', 0, 'deleted_contacts', 0);
  END IF;

  -- LinkedIn journeys and their open actions have no foreign key to contacts: end them here.
  IF cardinality(v_contacts) > 0 THEN
    UPDATE public.campaign_sequence_actions a
    SET status = 'cancelled',
        updated_at = now(),
        metadata = coalesce(a.metadata, '{}'::jsonb) || jsonb_build_object('cancel_reason', 'contact_deleted')
    FROM public.campaign_contacts j
    WHERE a.campaign_contact_id = j.id
      AND j.organization_id = p_organization_id
      AND j.contact_id = ANY (v_contacts)
      AND a.status IN ('pending', 'ready_for_review', 'approved');
    GET DIAGNOSTICS v_actions = ROW_COUNT;

    UPDATE public.campaign_contacts j
    SET journey_state = 'cancelled',
        next_action_at = NULL,
        updated_at = now(),
        state_metadata = coalesce(j.state_metadata, '{}'::jsonb)
          || jsonb_build_object('cancel_reason', 'contact_deleted', 'cancelled_at', now())
    WHERE j.organization_id = p_organization_id
      AND j.contact_id = ANY (v_contacts)
      AND j.journey_state NOT IN ('completed', 'cancelled', 'failed', 'declined');
    GET DIAGNOSTICS v_journeys = ROW_COUNT;

    UPDATE public.reply_drafts d
    SET status = 'rejected',
        updated_at = now()
    WHERE d.organization_id = p_organization_id
      AND d.status = 'draft'
      AND d.contact_id = ANY (v_contacts);
    GET DIAGNOSTICS v_drafts = ROW_COUNT;
  END IF;

  -- Open tasks would otherwise stay pending with company_id / contact_id set to NULL.
  -- Calls are left to their own trigger and to delete_crm_deal, which cancel them on deletion.
  UPDATE public.tasks t
  SET status = 'cancelled'::public.task_status,
      updated_at = now(),
      metadata = coalesce(t.metadata, '{}'::jsonb) || jsonb_build_object(
        'cancelled_reason', CASE WHEN t.company_id = ANY (v_companies) THEN 'company_deleted' ELSE 'contact_deleted' END,
        'cancelled_by', 'crm_list_delete',
        'crm_list_id', p_list_id,
        'cancelled_at', now()
      )
  WHERE t.organization_id = p_organization_id
    AND (t.company_id = ANY (v_companies) OR t.contact_id = ANY (v_contacts))
    AND t.task_type IS DISTINCT FROM 'call'::public.task_type
    AND t.status IN (
      'pending'::public.task_status,
      'in_progress'::public.task_status,
      'scheduled'::public.task_status,
      'in_review'::public.task_status
    );
  GET DIAGNOSTICS v_tasks = ROW_COUNT;

  IF cardinality(v_contacts) > 0 THEN
    DELETE FROM public.contacts
    WHERE organization_id = p_organization_id
      AND id = ANY (v_contacts);
    GET DIAGNOSTICS v_deleted_contacts = ROW_COUNT;
  END IF;

  IF cardinality(v_companies) > 0 THEN
    DELETE FROM public.companies
    WHERE organization_id = p_organization_id
      AND id = ANY (v_companies);
    GET DIAGNOSTICS v_deleted_companies = ROW_COUNT;
  END IF;

  RETURN jsonb_build_object(
    'list_found', true,
    'deleted_companies', v_deleted_companies,
    'deleted_contacts', v_deleted_contacts,
    'cancelled_journeys', v_journeys,
    'cancelled_actions', v_actions,
    'rejected_drafts', v_drafts,
    'cancelled_tasks', v_tasks
  );
END;
$$;

COMMENT ON FUNCTION public.crm_list_delete_batch(text, uuid, integer) IS
  'KAN-334: one transaction of a CRM list delete. Called by the Modal job delete_crm_list until it returns 0 deleted. Never deletes outside the list.';

-- 5. Delete preview ------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.crm_list_delete_preview(
  p_organization_id text,
  p_list_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_result jsonb;
BEGIN
  IF NULLIF(btrim(p_organization_id), '') IS NULL OR p_list_id IS NULL THEN
    RAISE EXCEPTION 'Organization and list are required' USING ERRCODE = '22023';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.crm_lists WHERE id = p_list_id AND organization_id = p_organization_id
  ) THEN
    RETURN jsonb_build_object('list_found', false);
  END IF;

  WITH list_companies AS (
    SELECT c.id
    FROM public.companies c
    WHERE c.organization_id = p_organization_id
      AND c.crm_list_id = p_list_id::text
    UNION
    SELECT r.extracted_company_id
    FROM public.crm_raw_records r
    JOIN public.companies c ON c.id = r.extracted_company_id AND c.organization_id = p_organization_id
    WHERE r.list_id = p_list_id
      AND r.organization_id = p_organization_id
  ),
  candidate_contacts AS (
    SELECT cc.contact_id
    FROM public.company_contacts cc
    JOIN list_companies lc ON lc.id = cc.company_id
    WHERE cc.organization_id = p_organization_id
    UNION
    SELECT r.extracted_person_id
    FROM public.crm_raw_records r
    WHERE r.list_id = p_list_id
      AND r.organization_id = p_organization_id
      AND r.extracted_person_id IS NOT NULL
  ),
  list_contacts AS (
    SELECT p.contact_id
    FROM candidate_contacts p
    WHERE NOT EXISTS (
      SELECT 1
      FROM public.company_contacts other
      WHERE other.contact_id = p.contact_id
        AND other.company_id NOT IN (SELECT id FROM list_companies)
    )
  )
  SELECT jsonb_build_object(
    'list_found', true,
    'companies', (SELECT count(*) FROM list_companies),
    'contacts', (SELECT count(*) FROM list_contacts),
    'companies_in_campaigns', (
      SELECT count(DISTINCT cc.company_id)
      FROM public.campaign_companies cc
      JOIN public.campaigns cp ON cp.id = cc.campaign_id
      WHERE cc.organization_id = p_organization_id
        AND cc.company_id IN (SELECT id FROM list_companies)
        AND cp.status::text IN ('draft', 'active', 'paused', 'discovery_completed')
    ),
    'companies_with_deals', (
      SELECT count(DISTINCT d.company_id)
      FROM public.deals d
      WHERE d.organization_id = p_organization_id
        AND d.company_id IN (SELECT id FROM list_companies)
    ),
    'contacts_in_sequences', (
      SELECT count(DISTINCT j.contact_id)
      FROM public.campaign_contacts j
      WHERE j.organization_id = p_organization_id
        AND j.contact_id IN (SELECT contact_id FROM list_contacts)
        AND j.journey_state NOT IN ('completed', 'cancelled', 'failed', 'declined')
    )
  )
  INTO v_result;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.crm_list_delete_preview(text, uuid) IS
  'KAN-334: counts for the CRM list delete confirmation (companies, people, companies in live campaigns, companies with deals, people in sequences).';

-- 6. Move a pending review -----------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.move_company_review(
  p_organization_id text,
  p_company_id uuid,
  p_from_campaign_id uuid,
  p_to_campaign_id uuid,
  p_user_id text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_from public.campaigns%ROWTYPE;
  v_to public.campaigns%ROWTYPE;
  v_company public.companies%ROWTYPE;
  v_source_link public.campaign_companies%ROWTYPE;
  v_target_link public.campaign_companies%ROWTYPE;
  v_task public.tasks%ROWTYPE;
  v_target_task public.tasks%ROWTYPE;
  v_target_link_id uuid;
  v_rescore boolean := true;
  v_now timestamptz := now();
BEGIN
  IF NULLIF(btrim(p_organization_id), '') IS NULL OR p_company_id IS NULL
     OR p_from_campaign_id IS NULL OR p_to_campaign_id IS NULL OR NULLIF(btrim(p_user_id), '') IS NULL THEN
    RAISE EXCEPTION 'Organization, company, both campaigns and user are required' USING ERRCODE = '22023';
  END IF;

  IF p_from_campaign_id = p_to_campaign_id THEN
    RETURN jsonb_build_object('ok', false, 'code', 'same_campaign');
  END IF;

  SELECT * INTO v_from FROM public.campaigns WHERE id = p_from_campaign_id AND organization_id = p_organization_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'code', 'not_found', 'missing', 'from_campaign'); END IF;
  SELECT * INTO v_to FROM public.campaigns WHERE id = p_to_campaign_id AND organization_id = p_organization_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'code', 'not_found', 'missing', 'to_campaign'); END IF;

  IF v_to.status::text NOT IN ('active', 'paused') THEN
    RETURN jsonb_build_object('ok', false, 'code', 'target_not_allowed', 'target_status', v_to.status::text);
  END IF;

  -- Lock order: source link, then the review task. A parallel move waits here and then finds nothing.
  SELECT * INTO v_source_link
  FROM public.campaign_companies
  WHERE organization_id = p_organization_id
    AND campaign_id = p_from_campaign_id
    AND company_id = p_company_id
  FOR UPDATE;
  IF NOT FOUND THEN
    IF EXISTS (
      SELECT 1 FROM public.campaign_companies
      WHERE organization_id = p_organization_id
        AND company_id = p_company_id
        AND moved_from_campaign_id = p_from_campaign_id
    ) THEN
      RETURN jsonb_build_object('ok', false, 'code', 'already_moved');
    END IF;
    RETURN jsonb_build_object('ok', false, 'code', 'not_found', 'missing', 'source_link');
  END IF;

  SELECT * INTO v_task
  FROM public.tasks
  WHERE organization_id = p_organization_id
    AND company_id = p_company_id
    AND campaign_id = p_from_campaign_id
    AND task_type = 'company_verification'::public.task_type
  ORDER BY created_at DESC
  LIMIT 1
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'code', 'not_found', 'missing', 'review_task');
  END IF;

  IF v_source_link.status IS DISTINCT FROM 'pending' OR v_task.status IS DISTINCT FROM 'pending'::public.task_status THEN
    IF v_task.metadata ? 'moved_to_campaign_id' THEN
      RETURN jsonb_build_object('ok', false, 'code', 'already_moved');
    END IF;
    RETURN jsonb_build_object('ok', false, 'code', 'source_not_pending',
      'link_status', v_source_link.status, 'task_status', v_task.status::text);
  END IF;

  SELECT * INTO v_company FROM public.companies WHERE id = p_company_id AND organization_id = p_organization_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'code', 'not_found', 'missing', 'company'); END IF;
  IF v_company.processing_status IN ('approved', 'processing', 'extracting_contacts') THEN
    RETURN jsonb_build_object('ok', false, 'code', 'company_busy', 'processing_status', v_company.processing_status);
  END IF;

  -- A link in another live campaign would make the cron process the company there, not in the target.
  IF EXISTS (
    SELECT 1
    FROM public.campaign_companies cc
    JOIN public.campaigns cp ON cp.id = cc.campaign_id
    WHERE cc.organization_id = p_organization_id
      AND cc.company_id = p_company_id
      AND cc.campaign_id NOT IN (p_from_campaign_id, p_to_campaign_id)
      AND cp.status::text IN ('draft', 'active', 'paused', 'discovery_completed')
  ) THEN
    RETURN jsonb_build_object('ok', false, 'code', 'in_other_campaign');
  END IF;

  SELECT * INTO v_target_link
  FROM public.campaign_companies
  WHERE organization_id = p_organization_id
    AND campaign_id = p_to_campaign_id
    AND company_id = p_company_id
  FOR UPDATE;
  IF FOUND THEN
    IF v_target_link.status = 'approved' THEN
      RETURN jsonb_build_object('ok', false, 'code', 'already_in_target');
    ELSIF v_target_link.status = 'rejected' THEN
      RETURN jsonb_build_object('ok', false, 'code', 'declined_in_target', 'declined_at', v_target_link.updated_at);
    END IF;
  END IF;

  -- Review tasks are deduplicated per company and campaign (any status), so an earlier finished review in
  -- the target would stop the new one from ever being created. A pending one means it already waits there.
  SELECT * INTO v_target_task
  FROM public.tasks
  WHERE organization_id = p_organization_id
    AND company_id = p_company_id
    AND campaign_id = p_to_campaign_id
    AND task_type = 'company_verification'::public.task_type
  ORDER BY created_at DESC
  LIMIT 1;
  IF FOUND THEN
    IF v_target_task.status = 'pending'::public.task_status THEN
      v_rescore := false;
    ELSIF v_target_task.status = 'completed'::public.task_status AND v_target_link.status IS NOT DISTINCT FROM 'approved' THEN
      RETURN jsonb_build_object('ok', false, 'code', 'already_in_target');
    ELSE
      RETURN jsonb_build_object('ok', false, 'code', 'declined_in_target',
        'declined_at', coalesce(v_target_task.completed_at, v_target_task.updated_at));
    END IF;
  END IF;

  IF v_target_link.id IS NOT NULL THEN
    UPDATE public.campaign_companies
    SET status = 'pending',
        processing_status = CASE WHEN v_rescore THEN 'pending' ELSE processing_status END,
        blocked_by_icp = false,
        icp_failed_filters = '[]'::jsonb,
        moved_from_campaign_id = p_from_campaign_id,
        moved_at = v_now,
        moved_by = p_user_id,
        updated_at = v_now
    WHERE id = v_target_link.id;
    v_target_link_id := v_target_link.id;
  ELSE
    INSERT INTO public.campaign_companies (
      campaign_id, company_id, organization_id, status, processing_status,
      blocked_by_icp, icp_failed_filters, moved_from_campaign_id, moved_at, moved_by
    ) VALUES (
      p_to_campaign_id, p_company_id, p_organization_id, 'pending', 'pending',
      false, '[]'::jsonb, p_from_campaign_id, v_now, p_user_id
    )
    RETURNING id INTO v_target_link_id;
  END IF;

  DELETE FROM public.campaign_companies WHERE id = v_source_link.id;

  UPDATE public.tasks
  SET status = 'cancelled'::public.task_status,
      updated_at = v_now,
      metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
        'cancelled_reason', 'moved_to_campaign',
        'moved_to_campaign_id', p_to_campaign_id,
        'moved_at', v_now,
        'moved_by', p_user_id
      )
  WHERE id = v_task.id;

  IF v_rescore THEN
    UPDATE public.companies
    SET processing_status = 'scheduled',
        blocked_by_icp = false,
        updated_at = v_now
    WHERE id = p_company_id;
  END IF;

  INSERT INTO public.company_activities (
    organization_id, company_id, campaign_id, task_id, activity_type, title, created_by_user_id, metadata
  ) VALUES (
    p_organization_id, p_company_id, p_to_campaign_id, v_task.id, 'company_updated',
    format('Moved from %s to %s', v_from.name, v_to.name), p_user_id,
    jsonb_build_object('kind', 'moved_to_campaign', 'from_campaign_id', p_from_campaign_id,
      'to_campaign_id', p_to_campaign_id, 'rescore', v_rescore)
  );

  RETURN jsonb_build_object(
    'ok', true,
    'code', 'moved',
    'target_link_id', v_target_link_id,
    'target_status', v_to.status::text,
    'target_name', v_to.name,
    'source_name', v_from.name,
    'rescore', v_rescore
  );
END;
$$;

COMMENT ON FUNCTION public.move_company_review(text, uuid, uuid, uuid, text) IS
  'KAN-334: moves a pending company review to another active or paused campaign in one transaction. Refusal codes: not_found, target_not_allowed, same_campaign, source_not_pending, company_busy, in_other_campaign, already_in_target, declined_in_target, already_moved.';

-- 7. Grants: service_role only ------------------------------------------------------------------

REVOKE ALL ON FUNCTION public.crm_list_delete_batch(text, uuid, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.crm_list_delete_batch(text, uuid, integer) TO service_role;
REVOKE ALL ON FUNCTION public.crm_list_delete_preview(text, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.crm_list_delete_preview(text, uuid) TO service_role;
REVOKE ALL ON FUNCTION public.move_company_review(text, uuid, uuid, uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.move_company_review(text, uuid, uuid, uuid, text) TO service_role;

DO $$
DECLARE
  internal_functions text[] := ARRAY['crm_list_delete_batch', 'crm_list_delete_preview', 'move_company_review'];
  still_exposed text;
  lost_service_role text;
BEGIN
  SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.proname)
  INTO still_exposed
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.prokind = 'f' AND p.proname = ANY (internal_functions)
    AND (has_function_privilege('anon', p.oid, 'EXECUTE') OR has_function_privilege('authenticated', p.oid, 'EXECUTE'));
  IF still_exposed IS NOT NULL THEN
    RAISE EXCEPTION '400: anon or authenticated can still execute: %', still_exposed;
  END IF;

  SELECT string_agg(p.oid::regprocedure::text, ', ' ORDER BY p.proname)
  INTO lost_service_role
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.prokind = 'f' AND p.proname = ANY (internal_functions)
    AND NOT has_function_privilege('service_role', p.oid, 'EXECUTE');
  IF lost_service_role IS NOT NULL THEN
    RAISE EXCEPTION '400: service_role cannot execute: %', lost_service_role;
  END IF;

  RAISE NOTICE '400: % function(s) are service_role only', cardinality(internal_functions);
END $$;

-- Verification after apply (read-only):
-- SELECT proname, proacl FROM pg_proc WHERE proname IN ('crm_list_delete_batch', 'crm_list_delete_preview', 'move_company_review');
-- SELECT column_name FROM information_schema.columns WHERE table_name = 'crm_lists' AND column_name = 'delete_state';
-- SELECT public.crm_list_delete_preview('<org>', '<list>');
