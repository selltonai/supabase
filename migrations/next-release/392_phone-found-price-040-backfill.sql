-- Phone price change: a found phone number is billed $0.40 (was $0.60), backdated to 2026-10-01.
--
-- Operator decision 2026-10-08: the new price applies from 2026-10-01 00:00 UTC onwards. Rows written
-- after the Modal deploy already carry $0.40 (selltonai-modal fix/phone-price-040). This file reprices
-- the rows written at $0.60 between 2026-10-01 and the moment it runs.
--
-- Scope:
--   - Airscale phone finder rows billed at a $0.60 unit price (sellton_pricing.cost_per_lookup = 0.6),
--     created on or after 2026-10-01 00:00 UTC, not yet on an invoice: invoice_id IS NULL AND the row
--     is outside every billing_invoices period of its organization (older invoices billed their period
--     without always linking the rows, so an unlinked row can already have been charged).
--   - sellton_cost is scaled by 0.4 / 0.6 (one found phone = one row today, so $0.60 -> $0.40), the
--     stored sellton_pricing snapshot is set to 0.4 (backoffice estimates from it), and metadata
--     records the adjustment. original_cost (our Airscale buy cost) is unchanged.
--   - Misses are already $0 telemetry rows and are not touched.
--
-- Not in scope: rows linked to an invoice or inside an invoiced period. Weekly invoices are Stripe
-- invoices with auto_advance, so those rows were charged at $0.60; they need a Stripe credit of $0.20
-- per found phone. operations/phone-invoice-audit/2026-10-phone-price-040-invoiced.sql lists them per invoice.
--
-- Consumers:
--   - selltonai-modal billing: billing_usage_for_period_v1 sums sellton_cost over uninvoiced rows, so the
--     next weekly invoice uses the new amounts.
--   - selltonai usage analytics: usage_analytics_projection_before_update (migration 345) re-projects
--     each updated row, so dashboards and the usage page follow without a rebuild.
--
-- Order: deploy Modal fix/phone-price-040 FIRST, then apply this file. Rows written between this file
-- and a later Modal deploy would stay at $0.60. The predicate only matches $0.60 rows, so re-running
-- the UPDATE by hand later is harmless.
--
-- Data-only, additive metadata; no DDL.

UPDATE public.usage
SET
  sellton_cost = ROUND(sellton_cost * 0.4 / 0.6, 6),
  sellton_pricing = jsonb_set(sellton_pricing, '{cost_per_lookup}', to_jsonb(0.4)),
  metadata = metadata || jsonb_build_object(
    'billing_adjustment', 'phone-found-price-040-from-2026-10-01',
    'billing_adjusted_from_sellton_cost', sellton_cost,
    'billing_adjusted_at', NOW()
  )
WHERE provider = 'airscale'
  AND model_name IN ('airscale-phone_finder', 'airscale-phone-finder')
  AND created_at >= TIMESTAMPTZ '2026-10-01 00:00:00+00'
  AND invoice_id IS NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.billing_invoices bi
     WHERE bi.organization_id = usage.organization_id
       AND usage.created_at >= bi.period_start
       AND usage.created_at < bi.period_end
  )
  AND COALESCE(sellton_cost, 0) > 0
  AND jsonb_typeof(metadata) = 'object'
  AND jsonb_typeof(sellton_pricing) = 'object'
  AND jsonb_typeof(sellton_pricing -> 'cost_per_lookup') = 'number'
  AND (sellton_pricing ->> 'cost_per_lookup')::numeric = 0.6;

-- Verify (expect 0 rows still at $0.60 since 2026-10-01 among uninvoiced phone rows; the invoiced ones
-- are listed by the audit file):
-- SELECT invoice_id IS NULL AS unlinked, sellton_pricing ->> 'cost_per_lookup' AS unit_price,
--        count(*), sum(sellton_cost)
--   FROM public.usage
--  WHERE provider = 'airscale' AND model_name IN ('airscale-phone_finder', 'airscale-phone-finder')
--    AND created_at >= TIMESTAMPTZ '2026-10-01 00:00:00+00' AND sellton_cost > 0
--  GROUP BY 1, 2 ORDER BY 1, 2;
