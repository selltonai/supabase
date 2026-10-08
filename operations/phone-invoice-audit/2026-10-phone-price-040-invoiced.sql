-- Read only. Phone rows from 2026-10-01 that were already billed at $0.60 (linked to an invoice, or
-- inside an invoiced period) and so were NOT repriced by migration 392_phone-found-price-040-backfill.
-- Each needs a Stripe credit of (charged - 0.40 x phones) on the listed invoice. Run after 392.
BEGIN READ ONLY;
SET LOCAL statement_timeout = '30s';

WITH phone_rows AS (
  SELECT u.id, u.organization_id, u.created_at, u.sellton_cost, u.invoice_id
    FROM public.usage u
   WHERE u.provider = 'airscale'
     AND u.model_name IN ('airscale-phone_finder', 'airscale-phone-finder')
     AND u.created_at >= TIMESTAMPTZ '2026-10-01 00:00:00+00'
     AND COALESCE(u.sellton_cost, 0) > 0
     AND u.sellton_pricing ->> 'cost_per_lookup' = '0.6'
), billed AS (
  SELECT p.*, COALESCE(p.invoice_id, (
           SELECT bi.id FROM public.billing_invoices bi
            WHERE bi.organization_id = p.organization_id
              AND p.created_at >= bi.period_start AND p.created_at < bi.period_end
            ORDER BY bi.created_at DESC LIMIT 1)) AS billed_invoice_id,
         p.invoice_id IS NOT NULL AS linked
    FROM phone_rows p
)
SELECT b.organization_id, o.name AS organization, bi.id AS invoice_id, bi.stripe_invoice_id,
       bi.status, bi.period_start, bi.period_end,
       count(*) AS phones_at_060, count(*) FILTER (WHERE NOT b.linked) AS in_period_unlinked,
       round(sum(b.sellton_cost), 2) AS charged,
       round(sum(b.sellton_cost) * (1 - 0.4 / 0.6), 2) AS credit_due
  FROM billed b
  LEFT JOIN public.billing_invoices bi ON bi.id = b.billed_invoice_id
  LEFT JOIN public.organization o ON o.id = b.organization_id
 GROUP BY 1, 2, 3, 4, 5, 6, 7
 ORDER BY bi.period_start NULLS LAST, credit_due DESC;
-- A row with invoice_id NULL here means a $0.60 row on no invoice: 392 has not run yet, or the Modal
-- deploy came after it (rerun 392's UPDATE by hand).

ROLLBACK;
