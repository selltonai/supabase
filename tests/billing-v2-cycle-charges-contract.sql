-- Migration 446's contract: the per-workspace switch, the seat kind with its one-time backfill, and the ledger whose
-- unique key stops a double charge. Run by tests/run-billing-v2-cycle-charges-contract.sh on a disposable database,
-- after the bootstrap and 446 applied twice.
DO $$
DECLARE r record; n integer; inv uuid; t text;
BEGIN
  -- 1. No workspace has a cohort yet; only existing and new are accepted.
  IF (SELECT count(*) FROM public.organization WHERE billing_cohort IS NOT NULL) <> 0 THEN
    RAISE EXCEPTION 'an existing workspace already has a billing_cohort';
  END IF;
  UPDATE public.organization SET billing_cohort = 'existing' WHERE id = 'org_web';
  UPDATE public.organization SET billing_cohort = 'new' WHERE id = 'org_phone';
  BEGIN
    UPDATE public.organization SET billing_cohort = 'v1' WHERE id = 'org_c';
    RAISE EXCEPTION 'an unknown billing_cohort was accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;

  -- 2. Seat kind: phone for the mobile signup's seats, web for the rest; the second run of 446 changed nothing.
  IF (SELECT seat_kind FROM public.org_seats WHERE clerk_user_id = 'user_p1') <> 'phone' THEN
    RAISE EXCEPTION 'the mobile workspace seat was not backfilled to phone';
  END IF;
  IF (SELECT count(*) FROM public.org_seats WHERE clerk_user_id IN ('user_w1', 'user_c1') AND seat_kind = 'web') <> 2 THEN
    RAISE EXCEPTION 'a web workspace seat is not web';
  END IF;
  BEGIN
    UPDATE public.org_seats SET seat_kind = 'tablet' WHERE clerk_user_id = 'user_w1';
    RAISE EXCEPTION 'an unknown seat_kind was accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;

  -- 3. The ledger: defaults, and one row per fee per cycle.
  INSERT INTO public.billing_cycle_charges (organization_id, cycle_start, charge_key, seat_kind, weeks, amount_usd)
  VALUES ('org_web', DATE '2026-11-02', 'infrastructure', NULL, 4, 33.00) RETURNING * INTO r;
  IF r.status <> 'reserved' OR r.invoice_id IS NOT NULL THEN RAISE EXCEPTION 'bad defaults: %', row_to_json(r); END IF;

  BEGIN
    INSERT INTO public.billing_cycle_charges (organization_id, cycle_start, charge_key, weeks, amount_usd)
    VALUES ('org_web', DATE '2026-11-02', 'infrastructure', 4, 33.00);
    RAISE EXCEPTION 'the same fee was written twice for one cycle';
  EXCEPTION WHEN unique_violation THEN NULL; END;

  -- The way Modal reserves: ON CONFLICT DO NOTHING returns only the rows actually written.
  WITH ins AS (
    INSERT INTO public.billing_cycle_charges (organization_id, cycle_start, charge_key, seat_kind, weeks, amount_usd)
    VALUES ('org_web', DATE '2026-11-02', 'infrastructure', NULL, 4, 33.00),
           ('org_web', DATE '2026-11-02', 'seat:11111111-1111-1111-1111-111111111111', 'web', 4, 15.00)
    ON CONFLICT (organization_id, cycle_start, charge_key) DO NOTHING
    RETURNING charge_key
  ) SELECT count(*) INTO n FROM ins;
  IF n <> 1 THEN RAISE EXCEPTION 'a second reservation returned % rows, expected only the new seat row', n; END IF;

  -- The same key in the next cycle, and in another workspace, is a new fee.
  INSERT INTO public.billing_cycle_charges (organization_id, cycle_start, charge_key, weeks, amount_usd)
  VALUES ('org_web', DATE '2026-11-30', 'infrastructure', 4, 33.00),
         ('org_c', DATE '2026-11-02', 'infrastructure', 4, 33.00),
         ('org_web', DATE '2026-11-02', 'seat:11111111-1111-1111-1111-111111111111:upgrade', 2, 1.50),
         ('org_c', DATE '2026-11-02', 'waived:paused', 0, 0.00),
         ('org_c', DATE '2026-11-02', 'seat:member:user_2abcDEF', 4, 15.00);
  INSERT INTO public.billing_cycle_charges (organization_id, cycle_start, charge_key, weeks, amount_usd, status)
  VALUES ('org_c', DATE '2026-11-02', 'unbilled:2026-11-02', 0, 58.00, 'unbilled');
  BEGIN
    INSERT INTO public.billing_cycle_charges (organization_id, cycle_start, charge_key, weeks, amount_usd, status)
    VALUES ('org_c', DATE '2026-11-09', 'unbilled:2026-11-09', 0, 5.00, 'reserved');
    RAISE EXCEPTION 'an unbilled marker was accepted with a charging status';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.billing_cycle_charges (organization_id, cycle_start, charge_key, weeks, amount_usd, status)
    VALUES ('org_c', DATE '2026-11-09', 'infrastructure', 4, 33.00, 'unbilled');
    RAISE EXCEPTION 'a fee was accepted with status unbilled';
  EXCEPTION WHEN check_violation THEN NULL; END;

  -- 4. What the ledger refuses.
  BEGIN
    INSERT INTO public.billing_cycle_charges (organization_id, cycle_start, charge_key, weeks, amount_usd)
    VALUES ('org_web', DATE '2026-11-03', 'infrastructure', 4, 33.00);
    RAISE EXCEPTION 'a cycle start that is not a Monday was accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.billing_cycle_charges (organization_id, cycle_start, charge_key, weeks, amount_usd)
    VALUES ('org_web', DATE '2026-11-02', 'refund', 4, 33.00);
    RAISE EXCEPTION 'an unknown charge_key was accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.billing_cycle_charges (organization_id, cycle_start, charge_key, weeks, amount_usd)
    VALUES ('org_web', DATE '2026-12-28', 'infrastructure', 5, 33.00);
    RAISE EXCEPTION 'five weeks were accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.billing_cycle_charges (organization_id, cycle_start, charge_key, weeks, amount_usd)
    VALUES ('org_web', DATE '2026-12-28', 'infrastructure', 4, -1.00);
    RAISE EXCEPTION 'a negative amount was accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.billing_cycle_charges (organization_id, cycle_start, charge_key, weeks, amount_usd, status)
    VALUES ('org_web', DATE '2026-12-28', 'infrastructure', 4, 33.00, 'paid');
    RAISE EXCEPTION 'an unknown status was accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.billing_cycle_charges (organization_id, cycle_start, charge_key, seat_kind, weeks, amount_usd)
    VALUES ('org_web', DATE '2026-12-28', 'seat:x', 'tablet', 4, 15.00);
    RAISE EXCEPTION 'an unknown seat_kind was accepted on the ledger';
  EXCEPTION WHEN check_violation THEN NULL; END;

  -- 5. Marking a row invoiced, and what happens when the invoice row goes.
  INSERT INTO public.billing_invoices (organization_id, stripe_invoice_id, period_start, period_end)
  VALUES ('org_web', 'in_fixture_1', '2026-10-26', '2026-11-02') RETURNING id INTO inv;
  UPDATE public.billing_cycle_charges SET status = 'invoiced', invoice_id = inv
   WHERE organization_id = 'org_web' AND cycle_start = DATE '2026-11-02' AND charge_key = 'infrastructure'
  RETURNING * INTO r;
  IF r.updated_at < r.created_at THEN RAISE EXCEPTION 'updated_at did not move'; END IF;
  DELETE FROM public.billing_invoices WHERE id = inv;
  SELECT * INTO r FROM public.billing_cycle_charges
   WHERE organization_id = 'org_web' AND cycle_start = DATE '2026-11-02' AND charge_key = 'infrastructure';
  IF r.status <> 'invoiced' OR r.invoice_id IS NOT NULL THEN
    RAISE EXCEPTION 'deleting the invoice row must keep the ledger row (still invoiced, no invoice id): %', row_to_json(r);
  END IF;

  -- 6. The prepaid limit's deductions: one row per key and limit, and the remaining amount is a sum.
  INSERT INTO public.billing_allowance_deductions
    (organization_id, allowance_id, deduction_key, covers, amount_usd, period_start)
  VALUES ('org_web', '22222222-2222-2222-2222-222222222222', 'fee:2026-11-02:infrastructure', 'fee', 33.00, '2026-10-26')
  RETURNING * INTO r;
  IF r.status <> 'reserved' OR r.invoice_id IS NOT NULL THEN RAISE EXCEPTION 'bad deduction defaults: %', row_to_json(r); END IF;
  BEGIN
    INSERT INTO public.billing_allowance_deductions
      (organization_id, allowance_id, deduction_key, covers, amount_usd, period_start)
    VALUES ('org_web', '22222222-2222-2222-2222-222222222222', 'fee:2026-11-02:infrastructure', 'fee', 33.00, '2026-10-26');
    RAISE EXCEPTION 'the same deduction was written twice';
  EXCEPTION WHEN unique_violation THEN NULL; END;
  INSERT INTO public.billing_allowance_deductions
    (organization_id, allowance_id, deduction_key, covers, amount_usd, period_start)
  VALUES ('org_web', '22222222-2222-2222-2222-222222222222', 'usage:2026-10-26', 'usage', 12.34, '2026-10-26'),
         ('org_web', '33333333-3333-3333-3333-333333333333', 'usage:2026-10-26', 'usage', 1.00, '2026-10-26'),
         ('org_c', '44444444-4444-4444-4444-444444444444', 'invoice:2026-10-26', 'invoice', 12.00, '2026-10-26');
  IF (SELECT 500.00 - sum(amount_usd) FROM public.billing_allowance_deductions
       WHERE allowance_id = '22222222-2222-2222-2222-222222222222') <> 454.66 THEN
    RAISE EXCEPTION 'the remaining limit is not the amount minus the recorded deductions';
  END IF;
  BEGIN
    INSERT INTO public.billing_allowance_deductions
      (organization_id, allowance_id, deduction_key, covers, amount_usd, period_start)
    VALUES ('org_web', '22222222-2222-2222-2222-222222222222', 'usage:2026-11-02', 'usage', 0, '2026-11-02');
    RAISE EXCEPTION 'a deduction of zero was accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.billing_allowance_deductions
      (organization_id, allowance_id, deduction_key, covers, amount_usd, period_start)
    VALUES ('org_web', '22222222-2222-2222-2222-222222222222', 'refund', 'usage', 1, '2026-11-02');
    RAISE EXCEPTION 'an unknown deduction_key was accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.billing_allowance_deductions
      (organization_id, allowance_id, deduction_key, covers, amount_usd, period_start)
    VALUES ('org_web', '22222222-2222-2222-2222-222222222222', 'usage:2026-11-09', 'seats', 1, '2026-11-09');
    RAISE EXCEPTION 'an unknown covers value was accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;

  -- 7. Service role only.
  FOREACH t IN ARRAY ARRAY['billing_cycle_charges', 'billing_allowance_deductions'] LOOP
    IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = ('public.' || t)::regclass) THEN
      RAISE EXCEPTION 'RLS is off on %', t;
    END IF;
    IF (SELECT count(*) FROM pg_policies WHERE schemaname = 'public' AND tablename = t) <> 0 THEN
      RAISE EXCEPTION '% has a policy', t;
    END IF;
    IF has_table_privilege('anon', 'public.' || t, 'SELECT')
       OR has_table_privilege('authenticated', 'public.' || t, 'INSERT')
       OR NOT has_table_privilege('service_role', 'public.' || t, 'INSERT')
       OR NOT has_table_privilege('service_role', 'public.' || t, 'DELETE') THEN
      RAISE EXCEPTION 'wrong privileges on %', t;
    END IF;
  END LOOP;
END $$;

-- A seat moved to web after the backfill stays web when 446 runs again.
UPDATE public.org_seats SET seat_kind = 'web', seat_kind_changed_at = now(), seat_kind_changed_by = 'staff'
 WHERE clerk_user_id = 'user_p1';
\i migrations/next-release/446_billing-v2-cycle-charges.sql
DO $$ BEGIN
  IF (SELECT seat_kind FROM public.org_seats WHERE clerk_user_id = 'user_p1') <> 'web' THEN
    RAISE EXCEPTION 'a re-run of 446 turned a changed seat back to phone';
  END IF;
  IF (SELECT billing_cohort FROM public.organization WHERE id = 'org_web') <> 'existing' THEN
    RAISE EXCEPTION 'a re-run of 446 reset billing_cohort';
  END IF;
  IF (SELECT count(*) FROM public.billing_cycle_charges) <> 8
     OR (SELECT count(*) FROM public.billing_allowance_deductions) <> 4 THEN
    RAISE EXCEPTION 'a re-run of 446 changed the ledger or the deductions';
  END IF;
END $$;

-- The rollback removes exactly what 446 added, and 446 applies again after it.
BEGIN;
\i migrations/next-release/rollback/446_billing-v2-cycle-charges.rollback.sql
DO $$ BEGIN
  IF to_regclass('public.billing_cycle_charges') IS NOT NULL
     OR to_regclass('public.billing_allowance_deductions') IS NOT NULL THEN
    RAISE EXCEPTION 'rollback left a table';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public'
              AND ((table_name = 'organization' AND column_name = 'billing_cohort')
                OR (table_name = 'org_seats' AND column_name LIKE 'seat_kind%'))) THEN
    RAISE EXCEPTION 'rollback left a column';
  END IF;
  IF (SELECT count(*) FROM public.org_seats) <> 3 OR (SELECT count(*) FROM public.organization) <> 3 THEN
    RAISE EXCEPTION 'rollback lost a seat or a workspace';
  END IF;
END $$;
\i migrations/next-release/446_billing-v2-cycle-charges.sql
DO $$ BEGIN
  IF (SELECT count(*) FROM public.organization WHERE billing_cohort IS NULL) <> 3 THEN
    RAISE EXCEPTION '446 after the rollback did not leave every workspace undecided';
  END IF;
END $$;
ROLLBACK;
SELECT 'billing v2 cycle charges contract passed' AS result;
