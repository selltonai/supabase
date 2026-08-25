-- Organization lifecycle and billing-start contract test.
--
-- Run only against a disposable database after applying
-- release-next/356_organization-lifecycle-and-billing-start.sql:
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 \
--     -f tests/organization-lifecycle-billing-start.contract.sql

BEGIN;

SET LOCAL TIME ZONE 'UTC';

INSERT INTO public.organization (id, name, deleted)
VALUES
  ('billing-start-contract-org', 'Billing start contract', false),
  ('lifecycle-delete-contract-org', 'Lifecycle delete contract', false);

INSERT INTO public.billing_customers (
  organization_id,
  stripe_customer_id,
  stripe_payment_method_id,
  card_last4,
  auto_charge_enabled,
  billing_started_at
)
VALUES
  (
    'billing-start-contract-org',
    'cus_billing_start_contract',
    'pm_billing_start_contract',
    '4242',
    true,
    '2026-08-24T12:00:00Z'
  ),
  (
    'lifecycle-delete-contract-org',
    'cus_lifecycle_delete_contract',
    'pm_lifecycle_delete_contract',
    '1111',
    true,
    '2026-08-24T12:00:00Z'
  );

INSERT INTO public.usage (
  id,
  organization_id,
  session_id,
  provider,
  model_name,
  api_calls,
  total_tokens,
  user_id,
  created_at,
  metadata,
  original_cost,
  sellton_cost
)
VALUES
  (
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    'billing-start-contract-org',
    'billing-start-contract-before',
    'openai',
    'gpt-contract',
    1,
    100,
    'billing-start-contract-user',
    '2026-08-24T11:59:59Z',
    '{"service":"email_generation_service"}'::jsonb,
    0.5,
    5
  ),
  (
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    'billing-start-contract-org',
    'billing-start-contract-after',
    'openai',
    'gpt-contract',
    1,
    100,
    'billing-start-contract-user',
    '2026-08-24T12:00:01Z',
    '{"service":"email_generation_service"}'::jsonb,
    0.7,
    7
  );

DO $$
DECLARE
  v_billed_cost NUMERIC;
  v_result JSONB;
BEGIN
  SELECT COALESCE(SUM(total_sellton_cost), 0)
  INTO v_billed_cost
  FROM public.billing_usage_uninvoiced_by_service_user
  WHERE organization_id = 'billing-start-contract-org';

  IF v_billed_cost <> 7 THEN
    RAISE EXCEPTION 'expected only post-card usage cost 7, got %', v_billed_cost;
  END IF;

  SELECT public.set_organization_lifecycle_state(
    'billing-start-contract-org',
    'archive',
    'contract-test@sellton.ai'
  ) INTO v_result;

  IF NOT EXISTS (
    SELECT 1
    FROM public.organization
    WHERE id = 'billing-start-contract-org'
      AND archived_at IS NOT NULL
      AND archived_by = 'contract-test@sellton.ai'
      AND dispatch_suspended = true
      AND dispatch_suspended_reason = 'organization_archived'
  ) THEN
    RAISE EXCEPTION 'archive did not suspend the organization lifecycle';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.billing_customers
    WHERE organization_id = 'billing-start-contract-org'
      AND auto_charge_enabled = true
  ) THEN
    RAISE EXCEPTION 'archive did not disable invoice generation';
  END IF;

  SELECT public.set_organization_lifecycle_state(
    'lifecycle-delete-contract-org',
    'delete',
    'contract-test@sellton.ai'
  ) INTO v_result;

  IF NOT EXISTS (
    SELECT 1
    FROM public.organization
    WHERE id = 'lifecycle-delete-contract-org'
      AND deleted = true
      AND dispatch_suspended = true
      AND dispatch_suspended_reason = 'organization_deleted'
  ) THEN
    RAISE EXCEPTION 'delete did not soft-delete and suspend the organization';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.billing_customers
    WHERE organization_id = 'lifecycle-delete-contract-org'
      AND auto_charge_enabled = true
  ) THEN
    RAISE EXCEPTION 'delete did not disable invoice generation';
  END IF;
END;
$$;

ROLLBACK;
