-- Organization lifecycle and card-anchored billing start.
--
-- What changed:
--   - Adds organization.archived_at / archived_by for retained lifecycle history.
--   - Adds billing_customers.billing_started_at, set when the first card is stored.
--   - Makes billing aggregation views exclude usage created before billing_started_at.
--   - Adds a service-role lifecycle RPC that atomically archives/soft-deletes an
--     organization, suspends dispatch, and disables future invoice generation.
--
-- Projects depending on this:
--   - backoffice invokes set_organization_lifecycle_state from Org 360.
--   - selltonai-modal reads archived_at and billing_started_at for billing guards.
--   - selltonai reads archived_at through the shared organization access guard.
--   - selltonai-gmail-api already honors organization.dispatch_suspended.
--
-- Application code update:
--   - Deploy this migration before the matching stage branches of backoffice,
--     selltonai-modal, and selltonai.

ALTER TABLE public.organization
  ADD COLUMN IF NOT EXISTS archived_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS archived_by TEXT;

CREATE INDEX IF NOT EXISTS idx_organization_archived_at
  ON public.organization (archived_at)
  WHERE archived_at IS NOT NULL;

COMMENT ON COLUMN public.organization.archived_at IS
  'When set, the organization is retained for history but cannot work or generate new invoices.';

COMMENT ON COLUMN public.organization.archived_by IS
  'Backoffice actor that archived the organization.';

ALTER TABLE public.billing_customers
  ADD COLUMN IF NOT EXISTS billing_started_at TIMESTAMPTZ;

COMMENT ON COLUMN public.billing_customers.billing_started_at IS
  'First time a payment card was stored. Usage and recurring fees before this timestamp are not billable.';

-- Existing cardholders were already live before this contract. updated_at is the
-- closest durable signal for the historical card-save time; created_at is the
-- fallback for rows that have never been updated.
UPDATE public.billing_customers
SET billing_started_at = COALESCE(updated_at, created_at, now())
WHERE billing_started_at IS NULL
  AND (card_last4 IS NOT NULL OR stripe_payment_method_id IS NOT NULL);

CREATE INDEX IF NOT EXISTS idx_billing_customers_billing_started_at
  ON public.billing_customers (organization_id, billing_started_at)
  WHERE billing_started_at IS NOT NULL;

CREATE OR REPLACE VIEW public.billing_usage_daily_by_provider_user AS
SELECT
  usage.organization_id,
  DATE(usage.created_at AT TIME ZONE 'UTC') AS usage_date,
  usage.provider,
  usage.user_id,
  SUM(COALESCE(usage.original_cost, 0)) AS total_original_cost,
  SUM(COALESCE(usage.sellton_cost, 0)) AS total_sellton_cost,
  SUM(COALESCE(usage.total_tokens, 0)) AS total_tokens,
  SUM(COALESCE(usage.api_calls, 0)) AS total_api_calls,
  COUNT(*) AS total_records
FROM public.usage
JOIN public.billing_customers
  ON billing_customers.organization_id = usage.organization_id
 AND billing_customers.billing_started_at IS NOT NULL
 AND usage.created_at >= billing_customers.billing_started_at
WHERE usage.created_at IS NOT NULL
GROUP BY
  usage.organization_id,
  DATE(usage.created_at AT TIME ZONE 'UTC'),
  usage.provider,
  usage.user_id;

CREATE OR REPLACE VIEW public.billing_usage_uninvoiced_by_provider_user AS
SELECT
  usage.organization_id,
  DATE(usage.created_at AT TIME ZONE 'UTC') AS usage_date,
  usage.provider,
  usage.user_id,
  SUM(COALESCE(usage.original_cost, 0)) AS total_original_cost,
  SUM(COALESCE(usage.sellton_cost, 0)) AS total_sellton_cost,
  SUM(COALESCE(usage.total_tokens, 0)) AS total_tokens,
  SUM(COALESCE(usage.api_calls, 0)) AS total_api_calls,
  COUNT(*) AS total_records
FROM public.usage
JOIN public.billing_customers
  ON billing_customers.organization_id = usage.organization_id
 AND billing_customers.billing_started_at IS NOT NULL
 AND usage.created_at >= billing_customers.billing_started_at
WHERE usage.created_at IS NOT NULL
  AND usage.invoice_id IS NULL
GROUP BY
  usage.organization_id,
  DATE(usage.created_at AT TIME ZONE 'UTC'),
  usage.provider,
  usage.user_id;

CREATE OR REPLACE VIEW public.billing_usage_daily_by_service_user AS
SELECT
  usage.organization_id,
  DATE(usage.created_at AT TIME ZONE 'UTC') AS usage_date,
  usage.metadata->>'service' AS service,
  usage.user_id,
  SUM(COALESCE(usage.total_tokens, 0)) AS total_tokens,
  SUM(COALESCE(usage.sellton_cost, 0)) AS total_sellton_cost,
  COUNT(*) AS total_records
FROM public.usage
JOIN public.billing_customers
  ON billing_customers.organization_id = usage.organization_id
 AND billing_customers.billing_started_at IS NOT NULL
 AND usage.created_at >= billing_customers.billing_started_at
WHERE usage.created_at IS NOT NULL
GROUP BY
  usage.organization_id,
  DATE(usage.created_at AT TIME ZONE 'UTC'),
  usage.metadata->>'service',
  usage.user_id;

CREATE OR REPLACE VIEW public.billing_usage_uninvoiced_by_service_user AS
SELECT
  usage.organization_id,
  DATE(usage.created_at AT TIME ZONE 'UTC') AS usage_date,
  usage.metadata->>'service' AS service,
  usage.user_id,
  SUM(COALESCE(usage.total_tokens, 0)) AS total_tokens,
  SUM(COALESCE(usage.sellton_cost, 0)) AS total_sellton_cost,
  COUNT(*) AS total_records
FROM public.usage
JOIN public.billing_customers
  ON billing_customers.organization_id = usage.organization_id
 AND billing_customers.billing_started_at IS NOT NULL
 AND usage.created_at >= billing_customers.billing_started_at
WHERE usage.created_at IS NOT NULL
  AND usage.invoice_id IS NULL
GROUP BY
  usage.organization_id,
  DATE(usage.created_at AT TIME ZONE 'UTC'),
  usage.metadata->>'service',
  usage.user_id;

COMMENT ON VIEW public.billing_usage_daily_by_provider_user IS
  'Billing-only usage after the workspace first stored a card, grouped by UTC date/provider/user.';
COMMENT ON VIEW public.billing_usage_uninvoiced_by_provider_user IS
  'Uninvoiced billing-only usage after the workspace first stored a card.';
COMMENT ON VIEW public.billing_usage_daily_by_service_user IS
  'Billing-only usage after the workspace first stored a card, grouped by UTC date/service/user.';
COMMENT ON VIEW public.billing_usage_uninvoiced_by_service_user IS
  'Uninvoiced billing-only usage after the workspace first stored a card, grouped by service.';

GRANT SELECT ON TABLE public.billing_usage_daily_by_provider_user TO service_role;
GRANT SELECT ON TABLE public.billing_usage_uninvoiced_by_provider_user TO service_role;
GRANT SELECT ON TABLE public.billing_usage_daily_by_service_user TO service_role;
GRANT SELECT ON TABLE public.billing_usage_uninvoiced_by_service_user TO service_role;

CREATE OR REPLACE FUNCTION public.set_organization_lifecycle_state(
  p_organization_id TEXT,
  p_action TEXT,
  p_actor TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_now TIMESTAMPTZ := now();
  v_action TEXT := lower(trim(COALESCE(p_action, '')));
  v_organization public.organization%ROWTYPE;
BEGIN
  IF v_action NOT IN ('archive', 'delete') THEN
    RAISE EXCEPTION 'Unsupported organization lifecycle action: %', p_action
      USING ERRCODE = '22023';
  END IF;

  SELECT *
  INTO v_organization
  FROM public.organization
  WHERE id = p_organization_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Organization not found: %', p_organization_id
      USING ERRCODE = 'P0002';
  END IF;

  IF v_action = 'archive' THEN
    UPDATE public.organization
    SET archived_at = COALESCE(archived_at, v_now),
        archived_by = COALESCE(archived_by, NULLIF(trim(p_actor), '')),
        dispatch_suspended = true,
        dispatch_suspended_reason = 'organization_archived',
        dispatch_suspended_at = v_now
    WHERE id = p_organization_id;
  ELSE
    UPDATE public.organization
    SET deleted = true,
        dispatch_suspended = true,
        dispatch_suspended_reason = 'organization_deleted',
        dispatch_suspended_at = v_now
    WHERE id = p_organization_id;
  END IF;

  UPDATE public.billing_customers
  SET auto_charge_enabled = false,
      updated_at = v_now
  WHERE organization_id = p_organization_id;

  RETURN jsonb_build_object(
    'organization_id', p_organization_id,
    'action', v_action,
    'effective_at', v_now,
    'billing_disabled', true,
    'dispatch_suspended', true
  );
END;
$$;

REVOKE ALL ON FUNCTION public.set_organization_lifecycle_state(TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_organization_lifecycle_state(TEXT, TEXT, TEXT) TO service_role;
