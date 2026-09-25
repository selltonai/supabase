-- Read only. Supply campaign_id with psql -v campaign_id='<uuid>'.
\set ON_ERROR_STOP on
BEGIN READ ONLY;
SET LOCAL statement_timeout = '30s';

SELECT c.id AS campaign_id, c.name, c.organization_id, c.phone_discovery_mode,
       count(DISTINCT cc.contact_id) AS campaign_contacts,
       count(DISTINCT cc.contact_id) FILTER (WHERE nullif(trim(ct.phone), '') IS NOT NULL) AS contacts_with_phone
FROM public.campaigns c
LEFT JOIN public.campaign_companies cp ON cp.campaign_id = c.id AND cp.organization_id = c.organization_id
LEFT JOIN public.company_contacts cc ON cc.company_id = cp.company_id AND cc.organization_id = c.organization_id
LEFT JOIN public.contacts ct ON ct.id = cc.contact_id AND ct.organization_id = c.organization_id
WHERE c.id = :'campaign_id'::uuid
GROUP BY c.id, c.name, c.organization_id, c.phone_discovery_mode;

WITH target AS (
  SELECT id::text AS campaign_id, organization_id FROM public.campaigns WHERE id = :'campaign_id'::uuid
), phone_usage AS (
  SELECT u.* FROM public.usage u JOIN target t ON t.organization_id = u.organization_id
  WHERE u.campaign_id = t.campaign_id
    AND u.provider = 'airscale'
    AND (u.metadata ->> 'action' = 'phone_finder' OR u.model_name LIKE 'airscale-phone%')
)
SELECT date_trunc('week', u.created_at AT TIME ZONE 'UTC') AS usage_week_utc,
       coalesce(u.metadata ->> 'service', '<missing>') AS recorded_service,
       CASE WHEN u.metadata ->> 'cost_mode' = 'telemetry' THEN 'telemetry'
            WHEN u.metadata ->> 'phones_found' = '1' OR u.metadata ->> 'success' = 'true' THEN 'found'
            ELSE 'unknown_or_failed' END AS result,
       CASE WHEN i.status = 'paid' THEN 'paid_invoice_linked'
            WHEN i.id IS NULL AND paid_period.id IS NOT NULL THEN 'paid_period_unlinked'
            WHEN i.id IS NULL THEN 'no_invoice_link_or_paid_period'
            ELSE coalesce(i.status, 'unknown') END AS invoice_state,
       count(*) AS usage_rows,
       sum(coalesce(u.sellton_cost, 0)) AS customer_cost,
       sum(coalesce(u.original_cost, 0)) AS provider_cost
FROM phone_usage u
LEFT JOIN public.billing_invoices i ON i.id = u.invoice_id
LEFT JOIN public.billing_invoices paid_period ON paid_period.organization_id = u.organization_id
  AND u.created_at >= paid_period.period_start AND u.created_at < paid_period.period_end
  AND paid_period.status = 'paid'
GROUP BY 1, 2, 3, 4
ORDER BY 1, 2, 3, 4;

SELECT i.id, i.period_start, i.period_end, i.status, i.total,
       item ->> 'action' AS action,
       item ->> 'action_label' AS action_label,
       item ->> 'sellton_cost' AS line_cost
FROM public.billing_invoices i
JOIN public.campaigns c ON c.organization_id = i.organization_id
CROSS JOIN LATERAL jsonb_array_elements(i.line_items) item
WHERE c.id = :'campaign_id'::uuid
  AND i.period_end >= c.created_at
ORDER BY i.period_start DESC, action;

COMMIT;
