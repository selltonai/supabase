-- ============================================================
-- Migration: 349_crm-deal-manual-create
-- Date:      2026-07-17
-- Purpose:   Add the service-role contract for manual deal creation.
-- Projects:  selltonai-database/supabase (owner), selltonai (caller).
-- Contract:  Additive. Validates every organization-scoped reference and
--            preserves the one-open-deal-per-company invariant.
-- ============================================================

CREATE OR REPLACE FUNCTION public.create_crm_deal(
  p_organization_id TEXT,
  p_company_id UUID,
  p_primary_contact_id UUID,
  p_source_campaign_id UUID,
  p_owner_user_id TEXT,
  p_name TEXT,
  p_stage TEXT,
  p_amount NUMERIC,
  p_currency TEXT,
  p_actor_user_id TEXT
)
RETURNS public.deals
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_company_name TEXT;
  v_deal public.deals;
BEGIN
  SELECT c.name
  INTO v_company_name
  FROM public.companies c
  WHERE c.id = p_company_id
    AND c.organization_id = p_organization_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Company does not belong to the organization'
      USING ERRCODE = '23514';
  END IF;

  IF p_primary_contact_id IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM public.company_contacts cc
    WHERE cc.organization_id = p_organization_id
      AND cc.company_id = p_company_id
      AND cc.contact_id = p_primary_contact_id
  ) THEN
    RAISE EXCEPTION 'Primary contact is not linked to the company'
      USING ERRCODE = '23514';
  END IF;

  IF p_source_campaign_id IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM public.campaign_companies cc
    JOIN public.campaigns c ON c.id = cc.campaign_id
    WHERE cc.organization_id = p_organization_id
      AND cc.company_id = p_company_id
      AND cc.campaign_id = p_source_campaign_id
      AND c.organization_id = p_organization_id
  ) THEN
    RAISE EXCEPTION 'Source campaign is not linked to the company'
      USING ERRCODE = '23514';
  END IF;

  IF p_owner_user_id IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM public.user_organizations uo
    WHERE uo.organization_id = p_organization_id
      AND uo.user_id = p_owner_user_id
  ) THEN
    RAISE EXCEPTION 'Deal owner is not an organization member'
      USING ERRCODE = '23514';
  END IF;

  IF p_actor_user_id IS NOT NULL AND NOT EXISTS (
    SELECT 1
    FROM public.user_organizations uo
    WHERE uo.organization_id = p_organization_id
      AND uo.user_id = p_actor_user_id
  ) THEN
    RAISE EXCEPTION 'Deal actor is not an organization member'
      USING ERRCODE = '23514';
  END IF;

  IF p_stage NOT IN (
    'LEAD', 'MEETING_REQUESTED', 'MEETING_BOOKED', 'PRESENTATION',
    'NEGOTIATION', 'AGREEMENT', 'WON', 'LOST'
  ) THEN
    RAISE EXCEPTION 'Unsupported deal stage' USING ERRCODE = '22023';
  END IF;

  IF p_currency NOT IN ('USD', 'EUR', 'GBP') THEN
    RAISE EXCEPTION 'Unsupported deal currency' USING ERRCODE = '22023';
  END IF;

  IF p_amount IS NOT NULL AND p_amount < 0 THEN
    RAISE EXCEPTION 'Deal amount cannot be negative' USING ERRCODE = '22023';
  END IF;

  PERFORM SET_CONFIG('app.crm_actor', 'user', TRUE);
  PERFORM SET_CONFIG('app.crm_actor_user_id', COALESCE(p_actor_user_id, ''), TRUE);
  PERFORM SET_CONFIG('app.crm_contact_id', COALESCE(p_primary_contact_id::TEXT, ''), TRUE);

  INSERT INTO public.deals (
    organization_id,
    company_id,
    primary_contact_id,
    stage_contact_id,
    source_campaign_id,
    owner_user_id,
    name,
    stage,
    amount,
    currency,
    creation_source,
    closed_at
  ) VALUES (
    p_organization_id,
    p_company_id,
    p_primary_contact_id,
    NULL,
    p_source_campaign_id,
    p_owner_user_id,
    COALESCE(NULLIF(BTRIM(p_name), ''), v_company_name),
    p_stage,
    p_amount,
    p_currency,
    'manual',
    CASE WHEN p_stage IN ('WON', 'LOST') THEN NOW() ELSE NULL END
  )
  RETURNING * INTO v_deal;

  RETURN v_deal;
END;
$$;

REVOKE ALL ON FUNCTION public.create_crm_deal(TEXT, UUID, UUID, UUID, TEXT, TEXT, TEXT, NUMERIC, TEXT, TEXT)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_crm_deal(TEXT, UUID, UUID, UUID, TEXT, TEXT, TEXT, NUMERIC, TEXT, TEXT)
  TO service_role;

COMMENT ON FUNCTION public.create_crm_deal(TEXT, UUID, UUID, UUID, TEXT, TEXT, TEXT, NUMERIC, TEXT, TEXT) IS
  'Service-role-only manual deal creation with organization-scoped reference validation and user-actor audit context.';

-- Verify after apply:
-- SELECT has_function_privilege('service_role',
--   'public.create_crm_deal(text,uuid,uuid,uuid,text,text,text,numeric,text,text)',
--   'EXECUTE');
-- ============================================================
