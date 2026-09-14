-- Explicit, invoice-specific repair after the read-only audit and backup.
-- Requires org_id and invoice_id psql variables. Never creates/pays invoices.
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '30s';
SELECT set_config('billing_repair.org_id', :'org_id', true);
SELECT set_config('billing_repair.invoice_id', :'invoice_id', true);
DO $$
DECLARE
  invoice public.billing_invoices;
  usage_total numeric;
  line_total numeric;
  candidate_ids uuid[];
BEGIN
  SELECT * INTO STRICT invoice FROM public.billing_invoices
  WHERE id=current_setting('billing_repair.invoice_id')::uuid
    AND organization_id=current_setting('billing_repair.org_id')
  FOR UPDATE;
  IF invoice.status NOT IN ('paid','open') OR invoice.usage_link_state NOT IN ('legacy','linked') THEN
    RAISE EXCEPTION 'Only reviewed legacy/linked paid or open invoices may be repaired';
  END IF;
  IF invoice.period_end > invoice.created_at OR invoice.period_start >= invoice.period_end THEN
    RAISE EXCEPTION 'Invoice period is not a completed positive interval';
  END IF;
  SELECT round(coalesce(sum((item->>'sellton_cost')::numeric),0),2) INTO line_total
  FROM jsonb_array_elements(invoice.line_items) item
  WHERE item->>'action' NOT IN ('platform_fee','seat_fee');
  IF line_total <> invoice.subtotal THEN
    RAISE EXCEPTION 'Invoice line items do not reconcile with its subtotal';
  END IF;
  -- Lock the exact candidate rows before validation, including partially linked
  -- rows. Rows already owned by a different invoice can never be reassigned.
  SELECT array_agg(locked.id), round(coalesce(sum(locked.sellton_cost),0),2)
  INTO candidate_ids, usage_total
  FROM (
    SELECT id, sellton_cost FROM public.usage
    WHERE organization_id=invoice.organization_id
      AND created_at>=invoice.period_start AND created_at<invoice.period_end
      AND (invoice_id IS NULL OR invoice_id=invoice.id)
    ORDER BY id FOR UPDATE
  ) locked;
  IF usage_total <> invoice.subtotal THEN
    RAISE EXCEPTION 'Manual reconciliation required: period usage % differs from invoice subtotal %', usage_total, invoice.subtotal;
  END IF;
  UPDATE public.usage SET invoice_id=invoice.id
  WHERE organization_id=invoice.organization_id
    AND created_at>=invoice.period_start AND created_at<invoice.period_end
    AND id=ANY(candidate_ids) AND invoice_id IS NULL;
  UPDATE public.billing_invoices SET usage_link_state='linked', usage_link_attempted_at=now() WHERE id=invoice.id;
END $$;
COMMIT;
