-- Billing hotfix: service-grouped usage views for billing summaries
--
-- What changed:
--   - Adds the service/user billing aggregation views expected by selltonai-modal.
--   - Adds a partial index for current-cycle uninvoiced billing lookups.
--
-- Projects depending on this:
--   - selltonai-modal reads these views from /billing/usage and invoice creation.
--   - selltonai displays the resulting billing categories on the Billing page.
--
-- Application code update:
--   - Required together with selltonai-modal billing code that reads
--     billing_usage_uninvoiced_by_service_user and
--     billing_usage_daily_by_service_user.

CREATE INDEX IF NOT EXISTS idx_usage_uninvoiced_org_created_service_user
  ON public.usage (organization_id, created_at DESC, (metadata->>'service'), user_id)
  WHERE invoice_id IS NULL;

CREATE OR REPLACE VIEW public.billing_usage_daily_by_service_user AS
SELECT
  organization_id,
  DATE(created_at) AS usage_date,
  metadata->>'service' AS service,
  user_id,
  SUM(COALESCE(total_tokens, 0)) AS total_tokens,
  SUM(COALESCE(sellton_cost, 0)) AS total_sellton_cost,
  COUNT(*) AS total_records
FROM public.usage
WHERE created_at IS NOT NULL
GROUP BY organization_id, DATE(created_at), metadata->>'service', user_id;

COMMENT ON VIEW public.billing_usage_daily_by_service_user IS
  'Billing aggregation: usage grouped by org/date/service/user. Used by billing UI action grouping. Regular VIEW; always fresh.';

CREATE OR REPLACE VIEW public.billing_usage_uninvoiced_by_service_user AS
SELECT
  organization_id,
  DATE(created_at) AS usage_date,
  metadata->>'service' AS service,
  user_id,
  SUM(COALESCE(total_tokens, 0)) AS total_tokens,
  SUM(COALESCE(sellton_cost, 0)) AS total_sellton_cost,
  COUNT(*) AS total_records
FROM public.usage
WHERE created_at IS NOT NULL
  AND invoice_id IS NULL
GROUP BY organization_id, DATE(created_at), metadata->>'service', user_id;

COMMENT ON VIEW public.billing_usage_uninvoiced_by_service_user IS
  'Billing aggregation: uninvoiced usage grouped by org/date/service/user. Used by current billing summaries and invoice generation.';

GRANT SELECT ON TABLE public.billing_usage_daily_by_service_user TO service_role;
GRANT SELECT ON TABLE public.billing_usage_uninvoiced_by_service_user TO service_role;
