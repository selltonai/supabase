DO $$
BEGIN
  IF (SELECT invoice_id FROM usage WHERE id='eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee') IS DISTINCT FROM 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'::uuid THEN
    RAISE EXCEPTION 'verified legacy usage was not linked';
  END IF;
  IF EXISTS (SELECT 1 FROM usage WHERE id IN ('ffffffff-ffff-4fff-8fff-ffffffffffff','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb') AND invoice_id IS NOT NULL) THEN
    RAISE EXCEPTION 'repair changed another period/org or persisted a mismatched repair';
  END IF;
  IF (SELECT usage_link_state FROM billing_invoices WHERE id='dddddddd-dddd-4ddd-8ddd-dddddddddddd') <> 'legacy' THEN
    RAISE EXCEPTION 'failed repair was not rolled back';
  END IF;
END $$;
