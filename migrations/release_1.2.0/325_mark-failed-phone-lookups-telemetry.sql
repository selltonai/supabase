-- Phone billing hotfix: failed Airscale phone lookups are telemetry, not customer-billable.
--
-- What changed:
--   - Uninvoiced failed phone lookup rows keep original_cost/api_calls for internal observability.
--   - Customer-facing sellton_cost is reset to 0.00 and metadata marks the row as telemetry.
--
-- Dependent projects:
--   - selltonai-modal: new tracking writes failed phone lookups with telemetry_only=true.
--   - selltonai: phone analytics reads sellton_cost and metadata outcome counts.
--
-- Application code:
--   - Deploy together with the phone discovery tracking fix so new failed lookups are inserted correctly.
--   - Already-invoiced rows are intentionally not changed here; paid invoices require manual credit handling.

UPDATE public.usage
SET
  output_tokens = 0,
  total_tokens = 0,
  sellton_cost = 0,
  metadata = COALESCE(metadata, '{}'::jsonb)
    || jsonb_build_object(
      'cost_mode', 'telemetry',
      'billing_adjustment', 'failed-phone-lookup-not-billable',
      'billing_adjusted_at', NOW()
    )
WHERE provider = 'airscale'
  AND model_name IN ('airscale-phone_finder', 'airscale-phone-finder')
  AND jsonb_typeof(metadata) = 'object'
  AND COALESCE(metadata->>'action', 'phone_finder') = 'phone_finder'
  AND LOWER(COALESCE(metadata->>'success', 'false')) NOT IN ('true', '1', 'yes')
  AND invoice_id IS NULL
  AND COALESCE(sellton_cost, 0) > 0;
