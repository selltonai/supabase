-- REVIEW BEFORE APPLY. This corrects only the displayed category on IGA's
-- already-paid September 7-14 invoice. It does not change the charge, totals,
-- Stripe invoice, usage rows, or invoice links. Run only after a fresh audit
-- and explicit approval to amend the paid invoice's stored line items.
BEGIN;
SET LOCAL statement_timeout = '30s';
SET LOCAL lock_timeout = '3s';

DO $$
DECLARE
  invoice_row public.billing_invoices%ROWTYPE;
  contact_line jsonb;
  phone_count bigint;
  successful_phone_count bigint;
  distinct_phone_contacts bigint;
  unlinked_phone_count bigint;
  phone_cost numeric;
  phone_tokens bigint;
  period_usage_cost numeric;
  old_line_total numeric;
  new_line_total numeric;
  corrected_lines jsonb;
BEGIN
  SELECT * INTO STRICT invoice_row
  FROM public.billing_invoices
  WHERE id = 'c32c073f-00a3-4585-b815-6dd3bc7f511b'
  FOR UPDATE;

  IF invoice_row.organization_id <> 'org_3A7OJMfeVlS7oSbTE2sOO9TATWM'
     OR invoice_row.stripe_invoice_id <> 'in_1UFNLFFUOomX1SdJ5OC0oqwG'
     OR invoice_row.status <> 'paid'
     OR invoice_row.usage_link_state <> 'legacy'
     OR invoice_row.period_start <> '2026-09-07 00:00:00+00'::timestamptz
     OR invoice_row.period_end <> '2026-09-14 00:00:00+00'::timestamptz
     OR invoice_row.subtotal <> 63.20
     OR invoice_row.total <> 82.70 THEN
    RAISE EXCEPTION 'IGA invoice identity, period, payment, or amount changed';
  END IF;

  SELECT count(*), count(*) FILTER (WHERE u.metadata ->> 'success' = 'true'
      AND u.metadata ->> 'phones_found' = '1'),
      count(DISTINCT u.metadata ->> 'contact_id'),
      count(*) FILTER (WHERE u.invoice_id IS NULL),
      coalesce(sum(u.sellton_cost), 0), coalesce(sum(u.total_tokens), 0)
  INTO phone_count, successful_phone_count, distinct_phone_contacts,
       unlinked_phone_count, phone_cost, phone_tokens
  FROM public.usage u
  WHERE u.organization_id = invoice_row.organization_id
    AND u.created_at >= invoice_row.period_start
    AND u.created_at < invoice_row.period_end
    AND u.provider = 'airscale'
    AND (u.metadata ->> 'action' = 'phone_finder'
         OR u.model_name LIKE 'airscale-phone%');

  SELECT round(coalesce(sum(u.sellton_cost), 0), 2)
  INTO period_usage_cost
  FROM public.usage u
  WHERE u.organization_id = invoice_row.organization_id
    AND u.created_at >= invoice_row.period_start
    AND u.created_at < invoice_row.period_end;

  IF phone_count <> 60 OR successful_phone_count <> 60
     OR distinct_phone_contacts <> 60 OR unlinked_phone_count <> 60
     OR phone_cost <> 36.00 OR phone_tokens <> 60
     OR period_usage_cost <> invoice_row.subtotal THEN
    RAISE EXCEPTION 'IGA phone usage no longer matches the paid invoice';
  END IF;

  IF (SELECT count(*) FROM jsonb_array_elements(invoice_row.line_items) item
      WHERE item ->> 'action' = 'contact_enrichment') <> 1
     OR (SELECT count(*) FROM jsonb_array_elements(invoice_row.line_items) item
      WHERE item ->> 'action' = 'phone_discovery') <> 0 THEN
    RAISE EXCEPTION 'IGA invoice categories no longer match the audited shape';
  END IF;

  SELECT item INTO contact_line
  FROM jsonb_array_elements(invoice_row.line_items) item
  WHERE item ->> 'action' = 'contact_enrichment';

  IF (contact_line ->> 'sellton_cost')::numeric <> 40.0905
     OR (contact_line ->> 'total_tokens')::bigint <> 115
     OR contact_line -> 'user_breakdown' <> '[{"cost":40.0905,"tokens":115,"user_id":null,"user_email":"Automation"}]'::jsonb THEN
    RAISE EXCEPTION 'IGA contact-enrichment line no longer matches the audited shape';
  END IF;

  SELECT jsonb_agg(
    CASE WHEN item.value ->> 'action' = 'contact_enrichment'
      THEN jsonb_set(
        jsonb_set(
          jsonb_set(item.value, '{sellton_cost}', to_jsonb(4.0905::numeric)),
          '{total_tokens}', to_jsonb(55)
        ),
        '{user_breakdown}',
        jsonb_build_array(
          jsonb_set(
            jsonb_set(item.value -> 'user_breakdown' -> 0,
              '{cost}', to_jsonb(4.0905::numeric)),
            '{tokens}', to_jsonb(55)
          )
        )
      )
      ELSE item.value END
    ORDER BY item.ordinality
  )
  INTO corrected_lines
  FROM jsonb_array_elements(invoice_row.line_items) WITH ORDINALITY AS item(value, ordinality);

  corrected_lines := corrected_lines || jsonb_build_array(
    jsonb_build_object(
      'action', 'phone_discovery',
      'action_label', 'Phone discovery',
      'sellton_cost', 36.00,
      'total_tokens', 60,
      'user_breakdown', jsonb_build_array(jsonb_build_object(
        'cost', 36.00, 'tokens', 60, 'user_id', NULL, 'user_email', 'Automation'
      ))
    )
  );

  SELECT sum((item ->> 'sellton_cost')::numeric)
  INTO old_line_total FROM jsonb_array_elements(invoice_row.line_items) item;
  SELECT sum((item ->> 'sellton_cost')::numeric)
  INTO new_line_total FROM jsonb_array_elements(corrected_lines) item;
  IF old_line_total <> new_line_total THEN
    RAISE EXCEPTION 'IGA invoice line-item total changed';
  END IF;

  UPDATE public.billing_invoices
  SET line_items = corrected_lines
  WHERE id = invoice_row.id AND line_items = invoice_row.line_items;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'IGA invoice changed before relabeling';
  END IF;
END $$;

SELECT id, status, subtotal, total, item ->> 'action' AS action,
       item ->> 'sellton_cost' AS cost
FROM public.billing_invoices
CROSS JOIN LATERAL jsonb_array_elements(line_items) item
WHERE id = 'c32c073f-00a3-4585-b815-6dd3bc7f511b'
  AND item ->> 'action' IN ('contact_enrichment', 'phone_discovery');

COMMIT;
