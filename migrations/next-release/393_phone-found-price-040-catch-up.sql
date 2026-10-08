-- Phone price catch-up: reprice the phones found between migration 392 and the Modal $0.40 deploy.
--
-- 392_phone-found-price-040-backfill was applied on 2026-10-08 before selltonai-modal fix/phone-price-040
-- was deployed, so Modal kept writing found phones at $0.60 after it ran. Operator decision 2026-10-08:
-- adjust only the unbilled week, no credits for weeks already invoiced.
--
-- MERGE ONLY AFTER the Modal deploy (production `devops/deploy.prod`, stage `devops/deploy.stage`).
-- Same UPDATE as 392: Airscale phone rows at a $0.60 unit price since 2026-10-01 00:00 UTC that no
-- invoice has billed (invoice_id IS NULL and outside every billing_invoices period of the org) become
-- $0.40. Already-billed weeks keep $0.60 by decision. Rows 392 already repriced no longer match.
-- The usage analytics projection follows via usage_analytics_projection_before_update (345).
--
-- Data-only, no DDL.

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

-- Verify after the Modal deploy (expect no unbilled $0.60 rows; newest rows show unit_price 0.4):
-- SELECT sellton_pricing ->> 'cost_per_lookup' AS unit_price, count(*), sum(sellton_cost), max(created_at)
--   FROM public.usage u
--  WHERE provider = 'airscale' AND model_name IN ('airscale-phone_finder', 'airscale-phone-finder')
--    AND created_at >= TIMESTAMPTZ '2026-10-01 00:00:00+00' AND sellton_cost > 0 AND invoice_id IS NULL
--    AND NOT EXISTS (SELECT 1 FROM public.billing_invoices bi WHERE bi.organization_id = u.organization_id
--                    AND u.created_at >= bi.period_start AND u.created_at < bi.period_end)
--  GROUP BY 1;
