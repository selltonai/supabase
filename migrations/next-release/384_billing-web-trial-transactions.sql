-- KAN-317: atomic, replayable backoffice web trial start/end.
-- Owner: supabase. Producer: backoffice. Later web/mobile trial writers must
-- use trial_product to distinguish their credits; Modal still consumes the ledger.
-- Depends on 382_billing-model.sql. Deploy before the updated backoffice.
-- Existing migrations remain unchanged. No invoice or existing API changes.
SET LOCAL lock_timeout = '10s';

ALTER TABLE public.billing_credits
  ADD COLUMN IF NOT EXISTS trial_product text CHECK (trial_product IS NULL OR (trial_product IN ('web', 'mobile') AND kind = 'trial'));

-- Only the old backoffice source is known to be a web trial. Unknown/card/mobile
-- sources are deliberately left untouched until their producer assigns a product.
UPDATE public.billing_credits SET trial_product = 'web'
WHERE kind = 'trial' AND source = 'backoffice_trial' AND trial_product IS NULL;

-- A receipt is committed with the dates and credit. Replaying a lost response
-- returns the original result, even when another action has since ended the trial.
CREATE TABLE IF NOT EXISTS public.billing_web_trial_operations (
  operation_id uuid PRIMARY KEY,
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  action text NOT NULL CHECK (action IN ('start', 'end')),
  actor text NOT NULL,
  result jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, action)
);
ALTER TABLE public.billing_web_trial_operations ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.billing_web_trial_operations FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON TABLE public.billing_web_trial_operations TO service_role;

CREATE OR REPLACE FUNCTION public.start_billing_web_trial(p_organization_id text, p_actor text, p_operation_id uuid, p_now timestamptz DEFAULT clock_timestamp())
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_receipt public.billing_web_trial_operations;
  v_customer public.billing_customers;
  v_days numeric;
  v_credit numeric;
  v_ends_at timestamptz;
  v_credit_id uuid;
  v_created_customer boolean;
  v_result jsonb;
BEGIN
  IF p_operation_id IS NULL OR NULLIF(btrim(p_actor), '') IS NULL OR p_now IS NULL OR NOT isfinite(p_now) THEN
    RAISE EXCEPTION 'A trial operation id, actor and finite timestamp are required.' USING ERRCODE = '22023';
  END IF;

  -- The same parent lock serializes Start and End, including a first customer row.
  PERFORM 1 FROM public.organization WHERE id = p_organization_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Organization not found.' USING ERRCODE = 'P0002'; END IF;

  SELECT * INTO v_receipt FROM public.billing_web_trial_operations WHERE operation_id = p_operation_id;
  IF FOUND THEN
    IF v_receipt.organization_id <> p_organization_id OR v_receipt.actor <> p_actor OR v_receipt.action <> 'start' THEN
      RAISE EXCEPTION 'That trial operation belongs to a different request.' USING ERRCODE = '22023';
    END IF;
    RETURN v_receipt.result;
  END IF;

  SELECT * INTO v_customer FROM public.billing_customers WHERE organization_id = p_organization_id FOR UPDATE;
  IF v_customer.trial_started_at IS NOT NULL OR EXISTS (
    SELECT 1 FROM public.billing_web_trial_operations WHERE organization_id = p_organization_id AND action = 'start'
  ) THEN
    RAISE EXCEPTION 'This organization already had a web trial. One trial per organization, ever.' USING ERRCODE = '23514';
  END IF;

  SELECT max(value) FILTER (WHERE key = 'trial_web_days'), max(value) FILTER (WHERE key = 'trial_web_credit_usd')
  INTO v_days, v_credit FROM public.billing_settings WHERE key IN ('trial_web_days', 'trial_web_credit_usd');
  IF v_days IS NULL OR v_days <> trunc(v_days) OR v_days NOT BETWEEN 1 AND 365
    OR v_credit IS NULL OR v_credit NOT BETWEEN 0 AND 99999999.99 THEN
    RAISE EXCEPTION 'Billing settings need trial_web_days (1 to 365) and trial_web_credit_usd (0 to 99999999.99) to start a web trial.' USING ERRCODE = '23514';
  END IF;
  v_ends_at := p_now + v_days::integer * interval '24 hours';

  INSERT INTO public.billing_customers (organization_id, status)
  VALUES (p_organization_id, 'active') ON CONFLICT (organization_id) DO NOTHING RETURNING id INTO v_customer.id;
  v_created_customer := FOUND;
  -- Recheck under the customer lock if another producer inserted the row meanwhile.
  SELECT * INTO v_customer FROM public.billing_customers WHERE organization_id = p_organization_id FOR UPDATE;
  IF v_customer.trial_started_at IS NOT NULL THEN
    RAISE EXCEPTION 'This organization already had a web trial. One trial per organization, ever.' USING ERRCODE = '23514';
  END IF;
  UPDATE public.billing_customers SET trial_started_at = p_now, trial_ends_at = v_ends_at,
    trial_granted_by = p_actor, updated_at = p_now WHERE organization_id = p_organization_id;

  IF v_credit > 0 THEN
    v_credit_id := gen_random_uuid();
    INSERT INTO public.billing_credits (id, organization_id, kind, trial_product, amount_usd, remaining_usd, source, expires_at, created_by)
    VALUES (v_credit_id, p_organization_id, 'trial', 'web', v_credit, v_credit, 'backoffice_trial', v_ends_at, p_actor);
  END IF;

  v_result := jsonb_build_object('trial_started_at', p_now, 'trial_ends_at', v_ends_at,
    'trial_days', v_days, 'trial_credit_usd', v_credit, 'credit_id', v_credit_id, 'created_customer_row', v_created_customer);
  INSERT INTO public.billing_web_trial_operations (operation_id, organization_id, action, actor, result)
  VALUES (p_operation_id, p_organization_id, 'start', p_actor, v_result);

  -- Audit failure is best effort, as in the existing backoffice write contract.
  -- The receipt prevents a replay from auditing twice.
  BEGIN
    INSERT INTO public.backoffice_audit_events (actor, action, organization_id, resource_type, resource_id, payload)
    VALUES (p_actor, 'billing.trial.started', p_organization_id, 'billing_customers', p_organization_id, v_result);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'Web trial start audit failed: %', SQLERRM;
  END;
  RETURN v_result;
END $$;

CREATE OR REPLACE FUNCTION public.end_billing_web_trial(p_organization_id text, p_actor text, p_operation_id uuid, p_now timestamptz DEFAULT clock_timestamp())
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_receipt public.billing_web_trial_operations;
  v_customer public.billing_customers;
  v_credit_ids uuid[];
  v_unused_credit numeric;
  v_result jsonb;
BEGIN
  IF p_operation_id IS NULL OR NULLIF(btrim(p_actor), '') IS NULL OR p_now IS NULL OR NOT isfinite(p_now) THEN
    RAISE EXCEPTION 'A trial operation id, actor and finite timestamp are required.' USING ERRCODE = '22023';
  END IF;

  PERFORM 1 FROM public.organization WHERE id = p_organization_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Organization not found.' USING ERRCODE = 'P0002'; END IF;

  SELECT * INTO v_receipt FROM public.billing_web_trial_operations WHERE operation_id = p_operation_id;
  IF FOUND THEN
    IF v_receipt.organization_id <> p_organization_id OR v_receipt.actor <> p_actor OR v_receipt.action <> 'end' THEN
      RAISE EXCEPTION 'That trial operation belongs to a different request.' USING ERRCODE = '22023';
    END IF;
    RETURN v_receipt.result;
  END IF;

  SELECT * INTO v_customer FROM public.billing_customers WHERE organization_id = p_organization_id FOR UPDATE;
  IF v_customer.trial_started_at IS NULL OR v_customer.trial_ends_at IS NULL OR v_customer.trial_ends_at <= p_now
    OR EXISTS (SELECT 1 FROM public.billing_web_trial_operations WHERE organization_id = p_organization_id AND action = 'end') THEN
    RAISE EXCEPTION 'No web trial is running for this organization.' USING ERRCODE = '23514';
  END IF;

  SELECT COALESCE(array_agg(id), ARRAY[]::uuid[]), COALESCE(sum(remaining_usd), 0)
  INTO v_credit_ids, v_unused_credit FROM (
    SELECT id, remaining_usd FROM public.billing_credits
    WHERE organization_id = p_organization_id AND kind = 'trial' AND trial_product = 'web' AND remaining_usd > 0
    ORDER BY id FOR UPDATE
  ) AS locked_credits;
  UPDATE public.billing_credits SET expires_at = p_now, remaining_usd = 0, updated_at = p_now
  WHERE id = ANY(v_credit_ids);
  UPDATE public.billing_customers SET trial_ends_at = p_now, updated_at = p_now WHERE organization_id = p_organization_id;

  v_result := jsonb_build_object('previous_trial_ends_at', v_customer.trial_ends_at, 'trial_ends_at', p_now,
    'closed_credit_ids', to_jsonb(v_credit_ids), 'unused_trial_credit_usd', v_unused_credit);
  INSERT INTO public.billing_web_trial_operations (operation_id, organization_id, action, actor, result)
  VALUES (p_operation_id, p_organization_id, 'end', p_actor, v_result);
  BEGIN
    INSERT INTO public.backoffice_audit_events (actor, action, organization_id, resource_type, resource_id, payload)
    VALUES (p_actor, 'billing.trial.ended', p_organization_id, 'billing_customers', p_organization_id, v_result);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'Web trial end audit failed: %', SQLERRM;
  END;
  RETURN v_result;
END $$;

REVOKE ALL ON FUNCTION public.start_billing_web_trial(text, text, uuid, timestamptz) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.end_billing_web_trial(text, text, uuid, timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.start_billing_web_trial(text, text, uuid, timestamptz) TO service_role;
GRANT EXECUTE ON FUNCTION public.end_billing_web_trial(text, text, uuid, timestamptz) TO service_role;
