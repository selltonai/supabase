-- Read-only. Usage: psql ... -v org_id='org_...' -f audit.sql
BEGIN READ ONLY;
SET LOCAL statement_timeout = '30s';
SELECT i.id, i.period_start, i.period_end, i.status, i.usage_link_state,
       i.subtotal AS invoice_usage, round(coalesce(sum(u.sellton_cost),0),2) AS matching_usage,
       count(u.id) AS usage_rows, count(u.id) FILTER (WHERE u.invoice_id IS NULL) AS unlinked_rows,
       CASE WHEN round(coalesce(sum(u.sellton_cost),0),2) = i.subtotal
            THEN 'subtotal_matches; validate line items before repair'
            ELSE 'manual_reconciliation_required' END AS assessment
FROM billing_invoices i
LEFT JOIN usage u ON u.organization_id=i.organization_id
  AND u.created_at>=i.period_start AND u.created_at<i.period_end
  AND (u.invoice_id IS NULL OR u.invoice_id=i.id)
WHERE i.organization_id=:'org_id' AND i.status IN ('paid','open')
GROUP BY i.id ORDER BY i.period_start;
COMMIT;
