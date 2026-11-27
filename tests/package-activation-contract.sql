-- Migrations 453 and 454's contract: the package tables and the three functions, every return status, retries,
-- the partial-finish path, the trial-ending path and its override, the grant conflict, the 10-attempt limit, and
-- full and partial refunds. Run by tests/run-package-activation-contract.sh on a disposable database, after the
-- bootstrap, the real 307, 422, 427, 428 and 446, and 453 and 454 applied twice each. One transaction: now() is the
-- same throughout. The two-session tests are in the runner.
CREATE OR REPLACE FUNCTION contract_fixture.check(ok boolean, what text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  IF ok IS NOT TRUE THEN RAISE EXCEPTION 'contract: %', what; END IF;
END $$;

-- A grant written by hand, as the backoffice's approve path writes one.
CREATE OR REPLACE FUNCTION contract_fixture.allowance(p_org text, p_kind text, p_reason text, p_amount numeric)
RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO public.workspace_allowances
    (organization_id, kind, amount_usd, expires_at, on_end, invoiced, reason, set_by, approved_by, approved_at, status)
  VALUES (p_org, p_kind, p_amount, now() + interval '7 days',
          CASE WHEN p_kind = 'trial' THEN 'pause' ELSE 'continue_billed' END,
          p_kind = 'prepaid', p_reason, 'staff@sellton.ai', 'staff@sellton.ai', now(), 'active')
  RETURNING id
$$;

INSERT INTO public.organization (id, name) VALUES
  ('org_card', 'Card Co'), ('org_paid_before', 'Paid Before'), ('org_partial_a', 'Partial A'),
  ('org_partial_b', 'Partial B'), ('org_mismatch', 'Mismatch'), ('org_unknown', 'Unknown'), ('org_trial', 'Trial'),
  ('org_budget', 'Budget'), ('org_manual', 'Manual'), ('org_conflict', 'Conflict'),
  ('org_acme', 'Acme'), ('org_carded', 'Carded'), ('org_carded_pm', 'Carded PM'), ('org_beta', 'Beta'),
  ('org_wrong', 'Wrong'), ('org_x', 'X'), ('org_y', 'Y'), ('org_del', 'Deleted'), ('org_arch', 'Archived'),
  ('org_job', 'Job'), ('org_job_cancelled', 'Job cancelled'), ('org_old', 'Old cohort'), ('org_granted', 'Granted'),
  ('org_spam', 'Spam'), ('org_old_spam', 'Old spam'), ('org_suspended', 'Suspended'),
  ('org_rf_full', 'Refund full'), ('org_rf_part', 'Refund part'), ('org_rf_drawn', 'Refund drawn'), ('org_dp', 'Dispute'),
  ('org_race_1', 'Race 1'), ('org_race_2', 'Race 2'), ('org_race_3', 'Race 3');

DO $$
DECLARE r jsonb; r2 jsonb; f record; a record; o record; id1 uuid; id2 uuid; n integer;
BEGIN
  -- 0. 453: the seed, and the rules on a code ------------------------------------------------------------
  PERFORM contract_fixture.check(
    (SELECT string_agg(format('%s:%s:%s:%s:%s:%s', id, label, price_usd, grant_usd, validity_days, shown_on_wall), ' ' ORDER BY sort)
       FROM public.billing_packages)
    = 'solo:Solo:500.00:250.00:90:t pilot:Pilot:2000.00:1000.00:90:t team:Team:4000.00:2000.00:90:f scale:Scale:8000.00:4000.00:180:f',
    'the package seed is B1''s');
  PERFORM contract_fixture.check(
    NOT has_table_privilege('anon', 'public.package_codes', 'SELECT')
    AND NOT has_table_privilege('authenticated', 'public.billing_packages', 'SELECT')
    AND has_table_privilege('service_role', 'public.package_code_attempts', 'INSERT')
    AND (SELECT bool_and(relrowsecurity) FROM pg_class
          WHERE oid IN ('public.billing_packages'::regclass, 'public.package_codes'::regclass,
                        'public.package_code_attempts'::regclass)),
    'the new tables are service role only, with RLS on');
  PERFORM contract_fixture.check(
    NOT has_function_privilege('anon', 'public.redeem_package_code(text, text, text, text)', 'EXECUTE')
    AND NOT has_function_privilege('authenticated', 'public.activate_package_checkout(text, text, text, integer, text, text, text)', 'EXECUTE')
    AND NOT has_function_privilege('authenticated', 'public.end_package_grant_for_payment(text, text, integer, integer)', 'EXECUTE')
    AND has_function_privilege('service_role', 'public.redeem_package_code(text, text, text, text)', 'EXECUTE')
    AND (SELECT bool_and(prosecdef AND proconfig = ARRAY['search_path=public']) FROM pg_proc
          WHERE proname IN ('activate_package_checkout', 'redeem_package_code', 'end_package_grant_for_payment')),
    'the functions are security definer with search_path public, service role only');

  BEGIN
    INSERT INTO public.package_codes (code, package_id, price_usd, email_domain, invoice_ref, expires_at, created_by)
    VALUES ('sell-lower', 'team', 4000, 'acme.com', 'INV', now() + interval '30 days', 'staff');
    RAISE EXCEPTION 'a lower-case code was accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.package_codes (code, package_id, price_usd, email_domain, email_exact, invoice_ref, expires_at, created_by)
    VALUES ('SELL-BOTH', 'team', 4000, 'acme.com', 'a@acme.com', 'INV', now() + interval '30 days', 'staff');
    RAISE EXCEPTION 'a code with both a domain and an address was accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.package_codes (code, package_id, price_usd, invoice_ref, expires_at, created_by)
    VALUES ('SELL-NONE', 'team', 4000, 'INV', now() + interval '30 days', 'staff');
    RAISE EXCEPTION 'a code with neither a domain nor an address was accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.package_codes (code, grant_usd, price_usd, email_domain, invoice_ref, expires_at, created_by)
    VALUES ('SELL-HALF', 1000, 2000, 'acme.com', 'INV', now() + interval '30 days', 'staff');
    RAISE EXCEPTION 'a custom code without its days was accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.package_codes (code, package_id, price_usd, email_domain, invoice_ref, expires_at, created_by)
    VALUES ('SELL-CASE', 'team', 4000, 'Acme.com', 'INV', now() + interval '30 days', 'staff');
    RAISE EXCEPTION 'an upper-case domain was accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.package_codes (code, package_id, price_usd, email_domain, invoice_ref, expires_at, created_by)
    VALUES ('SELL-MEGA', 'mega', 4000, 'acme.com', 'INV', now() + interval '30 days', 'staff');
    RAISE EXCEPTION 'a code for an unknown package was accepted';
  EXCEPTION WHEN foreign_key_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.activation_fees (organization_id, source) VALUES ('org_card', 'paypal');
    RAISE EXCEPTION 'an unknown activation source was accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;

  -- 1. activate_package_checkout: S1 (activated), S3 (retried: already_done) ----------------------------
  r := public.activate_package_checkout('cs_1', 'org_card', 'solo', 50000, 'USD', 'pi_1', 'user_1');
  PERFORM contract_fixture.check(r->>'status' = 'activated' AND r->>'ended_allowance_id' IS NULL, 'S1 activated: ' || r::text);
  SELECT * INTO f FROM public.activation_fees WHERE id = (r->>'activation_fee_id')::uuid;
  PERFORM contract_fixture.check(
    f.organization_id = 'org_card' AND f.amount_paid_cents = 50000 AND f.amount_discounted_cents = 0
    AND f.currency = 'usd' AND f.stripe_checkout_session_id = 'cs_1' AND f.stripe_payment_intent_id = 'pi_1'
    AND f.activated_by = 'user_1' AND f.source = 'stripe_checkout' AND f.package_id = 'solo'
    AND f.invoice_ref IS NULL AND f.invoiced_price_cents IS NULL
    AND f.metadata = '{"package": {"id": "solo", "label": "Solo", "price_usd": 500.00, "grant_usd": 250.00, "validity_days": 90}}'::jsonb,
    'S1 fee row: ' || row_to_json(f));
  SELECT * INTO a FROM public.workspace_allowances WHERE id = (r->>'allowance_id')::uuid;
  PERFORM contract_fixture.check(
    a.organization_id = 'org_card' AND a.kind = 'prepaid' AND a.status = 'active' AND a.invoiced
    AND a.amount_usd = 250.00 AND a.starts_at = now() AND a.expires_at = now() + interval '90 days'
    AND a.on_end = 'continue_billed' AND a.reason = 'Usage grant: Solo · pi_1'
    AND a.set_by = 'system:stripe_checkout' AND a.approved_by = 'system:stripe_checkout' AND a.approved_at = now()
    AND a.dedupe_key = 'checkout:cs_1' AND a.stripe_invoice_id IS NULL AND a.spent_usd = 0,
    'S1 grant row: ' || row_to_json(a));
  SELECT * INTO o FROM public.organization WHERE id = 'org_card';
  PERFORM contract_fixture.check(o.activation_paid_at = now() AND o.work_access_mode = 'auto'
                                 AND o.work_access_reason IS NULL AND NOT o.dispatch_suspended,
                                 'S1: activated, no override, not blocked');

  r2 := public.activate_package_checkout('cs_1', 'org_card', 'solo', 50000, 'usd', 'pi_1', 'user_1');
  PERFORM contract_fixture.check(r2->>'status' = 'already_done' AND r2->>'activation_fee_id' = r->>'activation_fee_id'
                                 AND r2->>'allowance_id' = r->>'allowance_id', 'S3 retry: ' || r2::text);
  PERFORM contract_fixture.check(
    (SELECT count(*) FROM public.activation_fees WHERE organization_id = 'org_card') = 1
    AND (SELECT count(*) FROM public.workspace_allowances WHERE organization_id = 'org_card') = 1,
    'S3: one fee row and one grant after the retry');

  -- An earlier activation date is kept.
  UPDATE public.organization SET activation_paid_at = '2026-01-01T00:00:00Z' WHERE id = 'org_paid_before';
  r := public.activate_package_checkout('cs_pb0', 'org_paid_before', 'pilot', 200000, 'usd', 'pi_pb0', 'user_2');
  PERFORM contract_fixture.check(r->>'status' = 'activated'
    AND (SELECT activation_paid_at FROM public.organization WHERE id = 'org_paid_before') = '2026-01-01T00:00:00Z',
    'an existing activation_paid_at is kept');

  -- 2. S4: the partial-finish path -------------------------------------------------------------------------
  -- The fee row is there (an attempt died after it), the grant and the activation are not.
  INSERT INTO public.activation_fees (organization_id, amount_paid_cents, stripe_checkout_session_id,
                                      stripe_payment_intent_id, source, package_id)
  VALUES ('org_partial_a', 200000, 'cs_pa', 'pi_pa', 'stripe_checkout', 'pilot') RETURNING id INTO id1;
  r := public.activate_package_checkout('cs_pa', 'org_partial_a', 'pilot', 200000, 'usd', 'pi_pa', 'user_3');
  PERFORM contract_fixture.check(r->>'status' = 'activated' AND (r->>'activation_fee_id')::uuid = id1
                                 AND r->>'allowance_id' IS NOT NULL, 'S4 fee present, grant missing: ' || r::text);
  PERFORM contract_fixture.check(
    (SELECT count(*) FROM public.activation_fees WHERE organization_id = 'org_partial_a') = 1
    AND (SELECT amount_usd FROM public.workspace_allowances WHERE dedupe_key = 'checkout:cs_pa') = 1000.00
    AND (SELECT activation_paid_at FROM public.organization WHERE id = 'org_partial_a') IS NOT NULL,
    'S4: the grant and the activation were finished, the fee row not doubled');
  r := public.activate_package_checkout('cs_pa', 'org_partial_a', 'pilot', 200000, 'usd', 'pi_pa', 'user_3');
  PERFORM contract_fixture.check(r->>'status' = 'already_done', 'S4 then a retry: ' || r::text);

  -- The grant is there, the fee row is not.
  INSERT INTO public.workspace_allowances
    (organization_id, kind, amount_usd, expires_at, on_end, invoiced, reason, set_by, approved_by, approved_at, status, dedupe_key)
  VALUES ('org_partial_b', 'prepaid', 250, now() + interval '90 days', 'continue_billed', true, 'Usage grant: Solo · pi_pb',
          'system:stripe_checkout', 'system:stripe_checkout', now(), 'active', 'checkout:cs_pbx') RETURNING id INTO id2;
  r := public.activate_package_checkout('cs_pbx', 'org_partial_b', 'solo', 50000, 'usd', 'pi_pb', 'user_4');
  PERFORM contract_fixture.check(r->>'status' = 'activated' AND (r->>'allowance_id')::uuid = id2
                                 AND r->>'activation_fee_id' IS NOT NULL, 'S4 grant present, fee missing: ' || r::text);
  PERFORM contract_fixture.check(
    (SELECT count(*) FROM public.workspace_allowances WHERE organization_id = 'org_partial_b') = 1
    AND (SELECT count(*) FROM public.activation_fees WHERE stripe_checkout_session_id = 'cs_pbx') = 1,
    'S4: no second grant');

  -- 3. amount_mismatch, unknown_package, unknown_organization, invalid_request ----------------------------
  r := public.activate_package_checkout('cs_mm', 'org_mismatch', 'pilot', 150000, 'usd', 'pi_mm', 'user_5');
  PERFORM contract_fixture.check(r->>'status' = 'amount_mismatch' AND r->>'allowance_id' IS NULL
                                 AND r->>'activation_fee_id' IS NOT NULL, 'amount_mismatch: ' || r::text);
  r := public.activate_package_checkout('cs_mm', 'org_mismatch', 'pilot', 150000, 'usd', 'pi_mm', 'user_5');
  PERFORM contract_fixture.check(r->>'status' = 'amount_mismatch', 'amount_mismatch retried: ' || r::text);
  PERFORM contract_fixture.check(
    (SELECT count(*) FROM public.activation_fees WHERE organization_id = 'org_mismatch') = 1
    AND (SELECT amount_paid_cents FROM public.activation_fees WHERE organization_id = 'org_mismatch') = 150000
    AND NOT EXISTS (SELECT 1 FROM public.workspace_allowances WHERE organization_id = 'org_mismatch')
    AND (SELECT activation_paid_at FROM public.organization WHERE id = 'org_mismatch') IS NOT NULL,
    'amount_mismatch: activated and the payment recorded once, no grant');

  r := public.activate_package_checkout('cs_unk', 'org_unknown', 'mega', 900000, 'usd', 'pi_unk', 'user_6');
  PERFORM contract_fixture.check(r->>'status' = 'unknown_package' AND r->>'allowance_id' IS NULL, 'unknown_package: ' || r::text);
  r := public.activate_package_checkout('cs_unk2', 'org_unknown', NULL, 50000, 'usd', 'pi_unk2', 'user_6');
  PERFORM contract_fixture.check(r->>'status' = 'unknown_package', 'no package id: ' || r::text);
  PERFORM contract_fixture.check(
    (SELECT count(*) FROM public.activation_fees WHERE organization_id = 'org_unknown' AND metadata = '{}'::jsonb) = 2
    AND NOT EXISTS (SELECT 1 FROM public.workspace_allowances WHERE organization_id = 'org_unknown'),
    'unknown_package: the payment recorded, no grant');

  r := public.activate_package_checkout('cs_ghost', 'org_ghost', 'solo', 50000, 'usd', 'pi_ghost', 'user_7');
  PERFORM contract_fixture.check(r->>'status' = 'unknown_organization', 'unknown_organization: ' || r::text);
  r := public.activate_package_checkout(NULL, 'org_card', 'solo', 50000, 'usd', 'pi_x', 'user_7');
  r2 := public.activate_package_checkout('  ', 'org_card', 'solo', 50000, 'usd', 'pi_x', 'user_7');
  PERFORM contract_fixture.check(r->>'status' = 'invalid_request' AND r2->>'status' = 'invalid_request',
                                 'invalid_request: ' || r::text || r2::text);
  PERFORM contract_fixture.check(NOT EXISTS (SELECT 1 FROM public.activation_fees WHERE stripe_payment_intent_id IN ('pi_ghost', 'pi_x')),
                                 'nothing written for an unknown workspace or a missing session');

  -- 4. S5: a running trial ends at payment, and its override goes back to auto -----------------------------
  id1 := contract_fixture.allowance('org_trial', 'trial', 'Web trial', 50);
  UPDATE public.organization
     SET work_access_mode = 'force_allow', work_access_reason = 'Allowance: trial allowance, 50.00 USD',
         work_access_until = now() + interval '7 days', work_access_updated_by = 'staff@sellton.ai'
   WHERE id = 'org_trial';
  r := public.activate_package_checkout('cs_tr', 'org_trial', 'pilot', 200000, 'usd', 'pi_tr', 'user_8');
  PERFORM contract_fixture.check(r->>'status' = 'activated' AND (r->>'ended_allowance_id')::uuid = id1, 'S5: ' || r::text);
  SELECT * INTO a FROM public.workspace_allowances WHERE id = id1;
  PERFORM contract_fixture.check(a.status = 'ended' AND a.ended_by = 'system:stripe_checkout' AND a.ended_at = now(),
                                 'S5: the trial ended: ' || row_to_json(a));
  SELECT * INTO o FROM public.organization WHERE id = 'org_trial';
  PERFORM contract_fixture.check(o.work_access_mode = 'auto' AND o.work_access_reason IS NULL AND o.work_access_until IS NULL
                                 AND o.work_access_updated_by = 'system:stripe_checkout' AND o.work_access_updated_at = now(),
                                 'S5: the trial''s override was reset to auto');
  PERFORM contract_fixture.check(
    (SELECT status FROM public.workspace_allowances WHERE id = (r->>'allowance_id')::uuid) = 'active'
    AND (SELECT count(*) FROM public.workspace_allowances WHERE organization_id = 'org_trial' AND status = 'active') = 1,
    'S5: the paid grant is the one active allowance');
  r := public.activate_package_checkout('cs_tr', 'org_trial', 'pilot', 200000, 'usd', 'pi_tr', 'user_8');
  PERFORM contract_fixture.check(r->>'status' = 'already_done', 'S5 retried: ' || r::text);

  -- A budget ends the same way.
  id1 := contract_fixture.allowance('org_budget', 'pilot', 'Pilot budget: agreed on the call', 300);
  r := public.activate_package_checkout('cs_bu', 'org_budget', 'solo', 50000, 'usd', 'pi_bu', 'user_9');
  PERFORM contract_fixture.check(r->>'status' = 'activated' AND (r->>'ended_allowance_id')::uuid = id1
                                 AND (SELECT status FROM public.workspace_allowances WHERE id = id1) = 'ended',
                                 'a running budget ends at payment: ' || r::text);

  -- A manual admin override (any other reason) is never touched.
  UPDATE public.organization SET work_access_mode = 'force_allow', work_access_reason = 'Sellton internal workspace'
   WHERE id = 'org_manual';
  r := public.activate_package_checkout('cs_ma', 'org_manual', 'solo', 50000, 'usd', 'pi_ma', 'user_10');
  PERFORM contract_fixture.check(r->>'status' = 'activated'
    AND (SELECT work_access_mode = 'force_allow' AND work_access_reason = 'Sellton internal workspace'
           FROM public.organization WHERE id = 'org_manual'),
    'a manual override stays: ' || r::text);

  -- 5. grant_conflict: a usage grant is already running (B14) ----------------------------------------------
  id1 := contract_fixture.allowance('org_conflict', 'prepaid', 'Usage grant: Team · INV-9', 2000);
  UPDATE public.organization SET work_access_mode = 'force_allow',
         work_access_reason = 'Allowance: prepaid allowance, 2000.00 USD' WHERE id = 'org_conflict';
  r := public.activate_package_checkout('cs_cf', 'org_conflict', 'solo', 50000, 'usd', 'pi_cf', 'user_11');
  PERFORM contract_fixture.check(r->>'status' = 'grant_conflict' AND (r->>'existing_allowance_id')::uuid = id1
                                 AND r->>'allowance_id' IS NULL AND r->>'activation_fee_id' IS NOT NULL,
                                 'grant_conflict: ' || r::text);
  PERFORM contract_fixture.check(
    (SELECT count(*) FROM public.workspace_allowances WHERE organization_id = 'org_conflict') = 1
    AND (SELECT status FROM public.workspace_allowances WHERE id = id1) = 'active'
    AND (SELECT work_access_mode = 'force_allow' FROM public.organization WHERE id = 'org_conflict'),
    'grant_conflict: no new grant, the running grant and its override untouched');
  r := public.activate_package_checkout('cs_cf', 'org_conflict', 'solo', 50000, 'usd', 'pi_cf', 'user_11');
  PERFORM contract_fixture.check(r->>'status' = 'grant_conflict'
    AND (SELECT count(*) FROM public.activation_fees WHERE organization_id = 'org_conflict') = 1,
    'grant_conflict retried: one fee row: ' || r::text);
END $$;

-- The codes the redemption tests use.
INSERT INTO public.package_codes (code, package_id, grant_usd, validity_days, price_usd, email_domain, email_exact,
                                  invoice_ref, note, expires_at, active, created_by) VALUES
  ('SELL-TEAM-AAAA', 'team', NULL, NULL, 4000, 'acme.com', NULL, 'INV-1', 'S6', now() + interval '30 days', true, 'staff@sellton.ai'),
  ('SELL-CUST-BBBB', NULL, 1500, 60, 3000, NULL, 'ceo@beta.io', 'INV-2', 'S25', now() + interval '30 days', true, 'staff@sellton.ai'),
  ('SELL-SCALE-CCC', 'scale', NULL, NULL, 8000, 'acme.com', NULL, 'INV-3', 'S7, S24', now() + interval '30 days', true, 'staff@sellton.ai'),
  ('SELL-OFF-DDDD', 'team', NULL, NULL, 4000, 'acme.com', NULL, 'INV-4', NULL, now() + interval '30 days', false, 'staff@sellton.ai'),
  ('SELL-OLD-EEEE', 'team', NULL, NULL, 4000, 'acme.com', NULL, 'INV-5', NULL, now() - interval '1 day', true, 'staff@sellton.ai'),
  ('SELL-USED-FFFF', 'team', NULL, NULL, 4000, 'acme.com', NULL, 'INV-6', NULL, now() + interval '30 days', true, 'staff@sellton.ai'),
  ('SELL-PILOT-001', 'pilot', NULL, NULL, 2000, 'example.com', NULL, 'INV-7', NULL, now() + interval '30 days', true, 'staff@sellton.ai'),
  ('SELL-PILOT-002', 'pilot', 1200, NULL, 2400, 'example.com', NULL, 'INV-8', 'a package with its own amount', now() + interval '30 days', true, 'staff@sellton.ai'),
  ('SELL-SPAM-HHHH', 'solo', NULL, NULL, 500, 'spam.io', NULL, 'INV-9', NULL, now() + interval '30 days', true, 'staff@sellton.ai'),
  ('SELL-SPAM-IIII', 'solo', NULL, NULL, 500, 'spam.io', NULL, 'INV-10', NULL, now() + interval '30 days', true, 'staff@sellton.ai'),
  ('SELL-RACE-GGGG', 'pilot', NULL, NULL, 2000, 'race.io', NULL, 'INV-11', 'S8', now() + interval '30 days', true, 'staff@sellton.ai');

DO $$
DECLARE r jsonb; r2 jsonb; c record; f record; rec record; o record; id1 uuid; i integer; expected jsonb; t text;
BEGIN
  -- 6. S6: a Team code at acme.com, no card -----------------------------------------------------------------
  r := public.redeem_package_code(' sell-team-aaaa ', 'org_acme', 'Jane@Acme.com', 'user_jane');
  PERFORM contract_fixture.check(
    (r->>'ok')::boolean AND (r->>'blocked')::boolean AND r->>'package_id' = 'team'
    AND (r->>'grant_usd')::numeric = 2000 AND (r->>'validity_days')::integer = 90 AND r->>'recommendation_id' IS NOT NULL
    AND NOT r ? 'already_redeemed',
    'S6: ' || r::text);
  SELECT * INTO c FROM public.package_codes WHERE code = 'SELL-TEAM-AAAA';
  PERFORM contract_fixture.check(c.redeemed_org_id = 'org_acme' AND c.redeemed_by = 'user_jane' AND c.redeemed_at = now()
                                 AND c.recommendation_id = (r->>'recommendation_id')::uuid, 'S6: the code is used');
  SELECT * INTO o FROM public.organization WHERE id = 'org_acme';
  PERFORM contract_fixture.check(o.activation_paid_at = now() AND o.dispatch_suspended
                                 AND o.dispatch_suspended_reason = 'card_required' AND o.dispatch_suspended_at = now()
                                 AND o.work_access_mode = 'auto', 'S6: activated and blocked for a card');
  SELECT * INTO f FROM public.activation_fees WHERE organization_id = 'org_acme';
  PERFORM contract_fixture.check(
    f.amount_paid_cents = 0 AND f.amount_discounted_cents = 0 AND f.source = 'package_code' AND f.package_id = 'team'
    AND f.invoice_ref = 'INV-1' AND f.invoiced_price_cents = 400000 AND f.activated_by = 'user_jane'
    AND f.metadata = '{"package_code": "SELL-TEAM-AAAA"}'::jsonb AND f.stripe_checkout_session_id IS NULL
    AND f.discount_code IS NULL AND f.paid_at = now(),
    'S6 fee row: ' || row_to_json(f));
  SELECT * INTO rec FROM public.cs_recommendations WHERE id = (r->>'recommendation_id')::uuid;
  -- The payload the backoffice's Commercial panel writes for a usage grant of kind prepaid (forms.ts and
  -- proposeCommercial), without expires_at, plus the package fields.
  expected := jsonb_build_object(
    'kind', 'prepaid', 'amount_usd', 2000.00, 'on_end', 'continue_billed', 'stripe_invoice_id', NULL,
    'invoiced', true, 'usage_grant', true,
    'preview', 'usage grant (deployment), 2000.00 USD for 90 days from approval, then regular billing',
    'requires_super_admin', true, 'source', 'package_code', 'validity_days', 90, 'invoice_ref', 'INV-1',
    'package_code', 'SELL-TEAM-AAAA', 'package_id', 'team');
  PERFORM contract_fixture.check(rec.payload = expected, 'S6 payload: ' || rec.payload::text);
  PERFORM contract_fixture.check(NOT rec.payload ? 'expires_at', 'S6: no expires_at in the payload');
  PERFORM contract_fixture.check(
    rec.organization_id = 'org_acme' AND rec.kind = 'allowance' AND rec.status = 'proposed'
    AND rec.title = 'usage grant (deployment), 2000.00 USD for 90 days from approval, then regular billing for Acme'
    AND rec.reason = 'Team · INV-1' AND rec.created_by = 'system:package_code'
    AND rec.dedupe_key = 'package_code:SELL-TEAM-AAAA' AND rec.expires_at IS NULL
    AND rec.grounding = '{"facts": [], "source": "package_code"}'::jsonb AND rec.approved_by IS NULL,
    'S6 recommendation row: ' || row_to_json(rec));
  PERFORM contract_fixture.check(NOT EXISTS (SELECT 1 FROM public.workspace_allowances WHERE organization_id = 'org_acme'),
                                 'S6: no grant before approval');

  -- Retried by the same workspace: the same answer, nothing written or counted.
  r2 := public.redeem_package_code('SELL-TEAM-AAAA', 'org_acme', 'jane@acme.com', 'user_jane');
  PERFORM contract_fixture.check((r2->>'ok')::boolean AND (r2->>'already_redeemed')::boolean
                                 AND r2->>'recommendation_id' = r->>'recommendation_id' AND (r2->>'blocked')::boolean
                                 AND (r2->>'grant_usd')::numeric = 2000 AND (r2->>'validity_days')::integer = 90,
                                 'S6 retried: ' || r2::text);
  PERFORM contract_fixture.check(
    (SELECT count(*) FROM public.cs_recommendations WHERE organization_id = 'org_acme') = 1
    AND (SELECT count(*) FROM public.activation_fees WHERE organization_id = 'org_acme') = 1
    AND NOT EXISTS (SELECT 1 FROM public.package_code_attempts WHERE organization_id = 'org_acme'),
    'S6 retried: one proposal, one fee row, no attempt');

  -- 7. S26: a card on file, by any of the three columns Modal reads: never blocked -------------------------
  INSERT INTO public.billing_customers (organization_id, card_last4) VALUES ('org_carded', '4242');
  INSERT INTO public.billing_customers (organization_id, stripe_payment_method_id) VALUES ('org_carded_pm', 'pm_1');
  -- Empty strings are no card (Python's bool('') is False).
  INSERT INTO public.billing_customers (organization_id, stripe_payment_method_id, card_last4, card_brand)
  VALUES ('org_beta', '', '', '');
  r := public.redeem_package_code('SELL-PILOT-001', 'org_carded', 'a@example.com', 'user_c');
  PERFORM contract_fixture.check((r->>'ok')::boolean AND NOT (r->>'blocked')::boolean
    AND (SELECT NOT dispatch_suspended AND dispatch_suspended_reason IS NULL FROM public.organization WHERE id = 'org_carded'),
    'S26 card_last4: ' || r::text);
  -- A package code with its own amount: the code's amount, the package's days.
  r := public.redeem_package_code('SELL-PILOT-002', 'org_carded_pm', 'b@example.com', 'user_d');
  PERFORM contract_fixture.check((r->>'ok')::boolean AND NOT (r->>'blocked')::boolean AND r->>'package_id' = 'pilot'
                                 AND (r->>'grant_usd')::numeric = 1200 AND (r->>'validity_days')::integer = 90,
                                 'S26 stripe_payment_method_id, own amount: ' || r::text);

  -- 8. S25: a custom code for one address ----------------------------------------------------------------------
  r := public.redeem_package_code('SELL-CUST-BBBB', 'org_beta', 'CEO@beta.io', 'user_ceo');
  PERFORM contract_fixture.check((r->>'ok')::boolean AND (r->>'blocked')::boolean AND r->>'package_id' IS NULL
                                 AND (r->>'grant_usd')::numeric = 1500 AND (r->>'validity_days')::integer = 60,
                                 'S25: ' || r::text);
  SELECT * INTO rec FROM public.cs_recommendations WHERE id = (r->>'recommendation_id')::uuid;
  PERFORM contract_fixture.check(
    rec.payload->'package_id' = 'null'::jsonb AND (rec.payload->>'amount_usd')::numeric = 1500
    AND (rec.payload->>'validity_days')::integer = 60 AND rec.reason = 'Custom · INV-2',
    'S25 payload: ' || rec.payload::text);
  PERFORM contract_fixture.check(
    (SELECT invoiced_price_cents = 300000 AND package_id IS NULL FROM public.activation_fees WHERE organization_id = 'org_beta'),
    'S25 fee row');

  -- 9. S7 and S9: every refusal, recorded, the code left unused ---------------------------------------------
  r := public.redeem_package_code('SELL-SCALE-CCC', 'org_wrong', 'bob@acme.co', 'user_bob');
  PERFORM contract_fixture.check(r = '{"ok": false, "reason": "email_mismatch"}'::jsonb, 'S7 wrong domain: ' || r::text);
  r := public.redeem_package_code('SELL-SCALE-CCC', 'org_wrong', 'bob@mail.acme.com', 'user_bob');
  PERFORM contract_fixture.check(r->>'reason' = 'email_mismatch', 'S7 a subdomain is another domain: ' || r::text);
  r := public.redeem_package_code('SELL-SCALE-CCC', 'org_wrong', 'acme.com', 'user_bob');
  PERFORM contract_fixture.check(r->>'reason' = 'email_mismatch', 'S7 not an address: ' || r::text);
  r := public.redeem_package_code('SELL-SCALE-CCC', 'org_wrong', NULL, 'user_bob');
  PERFORM contract_fixture.check(r->>'reason' = 'email_mismatch', 'S7 no email: ' || r::text);
  r := public.redeem_package_code('SELL-CUST-BBBB', 'org_wrong', 'cfo@beta.io', 'user_bob');
  PERFORM contract_fixture.check(r->>'reason' IN ('used'), 'an exact-address code already used: ' || r::text);
  PERFORM contract_fixture.check(
    (SELECT redeemed_at IS NULL FROM public.package_codes WHERE code = 'SELL-SCALE-CCC')
    AND (SELECT count(*) FROM public.package_code_attempts WHERE organization_id = 'org_wrong' AND reason = 'email_mismatch'
           AND code_tried = 'SELL-SCALE-CCC') = 4
    AND (SELECT activation_paid_at IS NULL FROM public.organization WHERE id = 'org_wrong')
    AND NOT EXISTS (SELECT 1 FROM public.cs_recommendations WHERE organization_id = 'org_wrong'),
    'S7: refused, counted, code unused, nothing activated');

  -- S24: the right domain then redeems the Scale code.
  r := public.redeem_package_code('SELL-SCALE-CCC', 'org_x', 'ops@acme.com', 'user_ops');
  PERFORM contract_fixture.check((r->>'ok')::boolean AND (r->>'grant_usd')::numeric = 4000
                                 AND (r->>'validity_days')::integer = 180, 'S24: ' || r::text);

  r := public.redeem_package_code('SELL-NOPE', 'org_y', 'y@acme.com', 'user_y');
  PERFORM contract_fixture.check(r = '{"ok": false, "reason": "not_found"}'::jsonb, 'not_found: ' || r::text);
  r := public.redeem_package_code('SELL-OFF-DDDD', 'org_y', 'y@acme.com', 'user_y');
  PERFORM contract_fixture.check(r->>'reason' = 'inactive', 'inactive: ' || r::text);
  r := public.redeem_package_code('SELL-OLD-EEEE', 'org_y', 'y@acme.com', 'user_y');
  PERFORM contract_fixture.check(r->>'reason' = 'expired', 'expired: ' || r::text);
  UPDATE public.package_codes SET redeemed_org_id = 'org_x', redeemed_by = 'user_ops', redeemed_at = now() - interval '1 day'
   WHERE code = 'SELL-USED-FFFF';
  r := public.redeem_package_code('SELL-USED-FFFF', 'org_y', 'y@acme.com', 'user_y');
  PERFORM contract_fixture.check(r->>'reason' = 'used', 'used by another workspace: ' || r::text);
  PERFORM contract_fixture.check(
    (SELECT string_agg(reason || ':' || code_tried, ',' ORDER BY reason) FROM public.package_code_attempts WHERE organization_id = 'org_y')
    = 'expired:SELL-OLD-EEEE,inactive:SELL-OFF-DDDD,not_found:SELL-NOPE,used:SELL-USED-FFFF',
    'each refusal is recorded with the code tried');

  -- The workspace refusals: archived (three markers, and a workspace that does not exist), existing cohort, a
  -- running grant. Each with a valid code and a matching address.
  UPDATE public.organization SET deleted = true WHERE id = 'org_del';
  UPDATE public.organization SET dispatch_suspended = true, dispatch_suspended_reason = 'archived' WHERE id = 'org_arch';
  INSERT INTO public.workspace_deletions (organization_id, mode, requested_by, reason)
  VALUES ('org_job', 'archive', 'boss@sellton.ai', 'contract test'),
         ('org_job_cancelled', 'archive', 'boss@sellton.ai', 'contract test');
  UPDATE public.workspace_deletions SET status = 'cancelled', cancelled_by = 'boss@sellton.ai', cancelled_at = now()
   WHERE organization_id = 'org_job_cancelled';
  UPDATE public.organization SET billing_cohort = 'existing' WHERE id = 'org_old';
  PERFORM contract_fixture.allowance('org_granted', 'goodwill', 'Usage grant: thanks for the feedback', 50);
  FOREACH t IN ARRAY ARRAY['org_del', 'org_arch', 'org_job', 'org_ghost'] LOOP
    r := public.redeem_package_code('SELL-RACE-GGGG', t, 'a@race.io', 'user_z');
    PERFORM contract_fixture.check(r->>'reason' = 'archived', 'archived ' || t || ': ' || r::text);
  END LOOP;
  r := public.redeem_package_code('SELL-RACE-GGGG', 'org_old', 'a@race.io', 'user_z');
  PERFORM contract_fixture.check(r->>'reason' = 'existing_cohort', 'existing_cohort: ' || r::text);
  r := public.redeem_package_code('SELL-RACE-GGGG', 'org_granted', 'a@race.io', 'user_z');
  PERFORM contract_fixture.check(r->>'reason' = 'already_activated_with_grant', 'already_activated_with_grant: ' || r::text);
  -- The order: the code's own refusals come first.
  r := public.redeem_package_code('SELL-OLD-EEEE', 'org_old', 'a@acme.com', 'user_z');
  PERFORM contract_fixture.check(r->>'reason' = 'expired', 'a code refusal before a workspace refusal: ' || r::text);
  r := public.redeem_package_code('SELL-RACE-GGGG', 'org_del', 'a@acme.com', 'user_z');
  PERFORM contract_fixture.check(r->>'reason' = 'email_mismatch', 'email_mismatch before archived: ' || r::text);
  PERFORM contract_fixture.check(
    (SELECT redeemed_at IS NULL FROM public.package_codes WHERE code = 'SELL-RACE-GGGG')
    AND NOT EXISTS (SELECT 1 FROM public.cs_recommendations WHERE organization_id IN ('org_del', 'org_arch', 'org_job', 'org_old', 'org_granted'))
    AND (SELECT count(*) FROM public.package_code_attempts WHERE organization_id = 'org_ghost' AND reason = 'archived') = 1,
    'workspace refusals: the code unused, nothing proposed, recorded (also for a workspace that does not exist)');
  -- A cancelled archive request is not an archive.
  INSERT INTO public.package_codes (code, package_id, price_usd, email_domain, invoice_ref, expires_at, created_by)
  VALUES ('SELL-BACK-0001', 'solo', 500, 'race.io', 'INV-12', now() + interval '30 days', 'staff@sellton.ai');
  r := public.redeem_package_code('SELL-BACK-0001', 'org_job_cancelled', 'a@race.io', 'user_z');
  PERFORM contract_fixture.check((r->>'ok')::boolean, 'a cancelled archive request does not refuse: ' || r::text);

  -- A workspace already paused for another reason keeps that reason.
  UPDATE public.organization SET dispatch_suspended = true, dispatch_suspended_reason = 'payment_failed',
         dispatch_suspended_at = '2026-11-01T00:00:00Z' WHERE id = 'org_suspended';
  INSERT INTO public.package_codes (code, package_id, price_usd, email_domain, invoice_ref, expires_at, created_by)
  VALUES ('SELL-SUSP-0001', 'solo', 500, 'race.io', 'INV-13', now() + interval '30 days', 'staff@sellton.ai');
  r := public.redeem_package_code('SELL-SUSP-0001', 'org_suspended', 'a@race.io', 'user_z');
  PERFORM contract_fixture.check((r->>'ok')::boolean AND (r->>'blocked')::boolean
    AND (SELECT dispatch_suspended_reason = 'payment_failed' AND dispatch_suspended_at = '2026-11-01T00:00:00Z'
           FROM public.organization WHERE id = 'org_suspended'),
    'an existing pause reason is kept: ' || r::text);

  -- 10. The 10-attempt limit -------------------------------------------------------------------------------------
  FOR i IN 1..10 LOOP
    r := public.redeem_package_code('SELL-GUESS-' || i, 'org_spam', 'a@spam.io', 'user_s');
    PERFORM contract_fixture.check(r->>'reason' = 'not_found', 'guess ' || i || ': ' || r::text);
  END LOOP;
  r := public.redeem_package_code('SELL-SPAM-HHHH', 'org_spam', 'a@spam.io', 'user_s');
  PERFORM contract_fixture.check(r = '{"ok": false, "reason": "too_many_attempts"}'::jsonb, 'the 11th try: ' || r::text);
  PERFORM contract_fixture.check(
    (SELECT redeemed_at IS NULL FROM public.package_codes WHERE code = 'SELL-SPAM-HHHH')
    AND (SELECT count(*) FROM public.package_code_attempts WHERE organization_id = 'org_spam') = 11
    AND (SELECT count(*) FROM public.package_code_attempts WHERE organization_id = 'org_spam' AND reason = 'too_many_attempts') = 1,
    'too_many_attempts: recorded, the valid code left unused');
  -- Attempts older than 24 hours do not count, and another workspace is not held back.
  INSERT INTO public.package_code_attempts (organization_id, code_tried, reason, created_at)
  SELECT 'org_old_spam', 'SELL-OLD-' || g, 'not_found', now() - interval '25 hours' FROM generate_series(1, 12) g;
  r := public.redeem_package_code('SELL-SPAM-IIII', 'org_old_spam', 'b@spam.io', 'user_t');
  PERFORM contract_fixture.check((r->>'ok')::boolean, 'attempts older than 24 hours do not count: ' || r::text);

  -- Execution as the service role (the app's key) works; a browser key cannot.
  SET LOCAL ROLE service_role;
  r := public.redeem_package_code('SELL-NOPE-2', 'org_y', 'y@acme.com', 'user_y');
  RESET ROLE;
  PERFORM contract_fixture.check(r->>'reason' = 'not_found', 'service_role executes: ' || r::text);
  BEGIN
    SET LOCAL ROLE anon;
    r := public.redeem_package_code('SELL-NOPE-3', 'org_y', 'y@acme.com', 'user_y');
    RAISE EXCEPTION 'anon executed redeem_package_code';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  RESET ROLE;
END $$;

-- 10b. One code per workspace: a second code waits while the first one's proposal is pending ------------------
INSERT INTO public.organization (id, name) VALUES
  ('org_two', 'Two codes'), ('org_two_ok', 'Two codes approved'), ('org_two_both', 'Two codes and a grant'),
  ('org_two_other', 'Another at two.io');
INSERT INTO public.package_codes (code, package_id, price_usd, email_domain, invoice_ref, expires_at, created_by)
SELECT 'SELL-TWO-000' || g, CASE WHEN g IN (3, 4) THEN 'team' ELSE 'solo' END, CASE WHEN g IN (3, 4) THEN 4000 ELSE 500 END,
       'two.io', 'INV-T' || g, now() + interval '30 days', 'staff@sellton.ai'
  FROM generate_series(1, 7) g;

DO $$
DECLARE r jsonb; r1 jsonb; id1 uuid;
BEGIN
  r1 := public.redeem_package_code('SELL-TWO-0001', 'org_two', 'a@two.io', 'user_two');
  PERFORM contract_fixture.check((r1->>'ok')::boolean, 'the first code: ' || r1::text);
  r := public.redeem_package_code('SELL-TWO-0002', 'org_two', 'a@two.io', 'user_two');
  PERFORM contract_fixture.check(r = '{"ok": false, "reason": "package_pending"}'::jsonb, 'a second code while pending: ' || r::text);
  PERFORM contract_fixture.check(
    (SELECT redeemed_at IS NULL FROM public.package_codes WHERE code = 'SELL-TWO-0002')
    AND (SELECT count(*) FROM public.package_code_attempts
          WHERE organization_id = 'org_two' AND reason = 'package_pending' AND code_tried = 'SELL-TWO-0002') = 1
    AND (SELECT count(*) FROM public.cs_recommendations WHERE organization_id = 'org_two') = 1
    AND (SELECT count(*) FROM public.activation_fees WHERE organization_id = 'org_two') = 1,
    'package_pending: recorded, the second code unused, nothing else written');
  -- The first code again is still a retry, not a refusal.
  r := public.redeem_package_code('SELL-TWO-0001', 'org_two', 'a@two.io', 'user_two');
  PERFORM contract_fixture.check((r->>'ok')::boolean AND (r->>'already_redeemed')::boolean
                                 AND r->>'recommendation_id' = r1->>'recommendation_id', 'the first code retried: ' || r::text);
  -- Another workspace is not held back by org_two's proposal.
  r := public.redeem_package_code('SELL-TWO-0007', 'org_two_other', 'b@two.io', 'user_other');
  PERFORM contract_fixture.check((r->>'ok')::boolean, 'another workspace: ' || r::text);

  -- Dismissed in Today: the second code goes through, with its own proposal.
  UPDATE public.cs_recommendations SET status = 'dismissed', dismissed_by = 'boss@sellton.ai', dismissed_at = now()
   WHERE id = (r1->>'recommendation_id')::uuid;
  r := public.redeem_package_code('SELL-TWO-0002', 'org_two', 'a@two.io', 'user_two');
  PERFORM contract_fixture.check((r->>'ok')::boolean AND r->>'recommendation_id' <> r1->>'recommendation_id'
    AND (SELECT count(*) FROM public.cs_recommendations WHERE organization_id = 'org_two' AND status = 'proposed') = 1,
    'after a dismissal: ' || r::text);

  -- Approved and granted (the backoffice's apply path): the rule as today, one grant at a time.
  r1 := public.redeem_package_code('SELL-TWO-0003', 'org_two_ok', 'a@two.io', 'user_ok');
  UPDATE public.cs_recommendations
     SET status = 'executed', approved_by = 'boss@sellton.ai', approved_at = now(), executed_at = now()
   WHERE id = (r1->>'recommendation_id')::uuid;
  id1 := contract_fixture.allowance('org_two_ok', 'prepaid', 'Usage grant: Team · INV-T3', 2000);
  r := public.redeem_package_code('SELL-TWO-0004', 'org_two_ok', 'a@two.io', 'user_ok');
  PERFORM contract_fixture.check(r->>'reason' = 'already_activated_with_grant', 'after an approval: ' || r::text);
  -- Once that grant has ended, a new code is accepted.
  UPDATE public.workspace_allowances SET status = 'ended', ended_by = 'system:stripe_refund', ended_at = now() WHERE id = id1;
  r := public.redeem_package_code('SELL-TWO-0004', 'org_two_ok', 'a@two.io', 'user_ok');
  PERFORM contract_fixture.check((r->>'ok')::boolean, 'after the grant ended: ' || r::text);

  -- The order: a running grant is named before a pending proposal.
  r1 := public.redeem_package_code('SELL-TWO-0005', 'org_two_both', 'a@two.io', 'user_both');
  PERFORM contract_fixture.allowance('org_two_both', 'goodwill', 'Usage grant: goodwill', 20);
  r := public.redeem_package_code('SELL-TWO-0006', 'org_two_both', 'a@two.io', 'user_both');
  PERFORM contract_fixture.check(r->>'reason' = 'already_activated_with_grant',
                                 'already_activated_with_grant before package_pending: ' || r::text);
END $$;

DO $$
DECLARE r jsonb; a record; id1 uuid;
BEGIN
  -- 11. S28: a full refund ends the grant ------------------------------------------------------------------------
  r := public.activate_package_checkout('cs_rf1', 'org_rf_full', 'solo', 50000, 'usd', 'pi_rf1', 'user_r');
  id1 := (r->>'allowance_id')::uuid;
  r := public.end_package_grant_for_payment('pi_rf1', 'refund', 50000, 50000);
  PERFORM contract_fixture.check(r->>'status' = 'ended' AND (r->>'allowance_id')::uuid = id1
                                 AND (r->>'amount_usd')::numeric = 250, 'S28 full refund: ' || r::text);
  SELECT * INTO a FROM public.workspace_allowances WHERE id = id1;
  PERFORM contract_fixture.check(a.status = 'ended' AND a.ended_by = 'system:stripe_refund' AND a.ended_at = now()
                                 AND a.amount_usd = 250, 'S28 grant row: ' || row_to_json(a));
  r := public.end_package_grant_for_payment('pi_rf1', 'refund', 50000, 50000);
  PERFORM contract_fixture.check(r->>'status' = 'unchanged' AND (r->>'allowance_id')::uuid = id1, 'S28 retried: ' || r::text);

  -- A dispute ends it too.
  r := public.activate_package_checkout('cs_dp', 'org_dp', 'solo', 50000, 'usd', 'pi_dp', 'user_r');
  id1 := (r->>'allowance_id')::uuid;
  r := public.end_package_grant_for_payment('pi_dp', 'dispute', 0, 50000);
  PERFORM contract_fixture.check(r->>'status' = 'ended'
    AND (SELECT ended_by FROM public.workspace_allowances WHERE id = id1) = 'system:stripe_dispute', 'dispute: ' || r::text);
  r := public.end_package_grant_for_payment('pi_dp', 'dispute', 0, 50000);
  PERFORM contract_fixture.check(r->>'status' = 'unchanged', 'dispute retried: ' || r::text);

  -- 12. S40: a partial refund reduces the grant by the same share ------------------------------------------------
  r := public.activate_package_checkout('cs_rf2', 'org_rf_part', 'pilot', 200000, 'usd', 'pi_rf2', 'user_r');
  id1 := (r->>'allowance_id')::uuid;
  -- The package is edited after the purchase: the refund still works from the grant as bought (1000).
  UPDATE public.billing_packages SET grant_usd = 1200 WHERE id = 'pilot';
  r := public.end_package_grant_for_payment('pi_rf2', 'refund', 100000, 200000);
  PERFORM contract_fixture.check(r->>'status' = 'reduced' AND (r->>'amount_usd')::numeric = 500.00, 'S40 half: ' || r::text);
  r := public.end_package_grant_for_payment('pi_rf2', 'refund', 100000, 200000);
  PERFORM contract_fixture.check(r->>'status' = 'unchanged' AND (r->>'amount_usd')::numeric = 500.00, 'S40 retried: ' || r::text);
  -- A second refund: Stripe's refunded total is now 1500 of 2000, a quarter is left.
  r := public.end_package_grant_for_payment('pi_rf2', 'refund', 150000, 200000);
  PERFORM contract_fixture.check(r->>'status' = 'reduced' AND (r->>'amount_usd')::numeric = 250.00, 'S40 more: ' || r::text);
  PERFORM contract_fixture.check(
    (SELECT status = 'active' AND amount_usd = 250.00 AND ended_at IS NULL FROM public.workspace_allowances WHERE id = id1),
    'S40: still active at the reduced amount');
  UPDATE public.billing_packages SET grant_usd = 1000 WHERE id = 'pilot';
  -- What is drawn since reaches the reduced amount: the same refund total arriving again ends it.
  INSERT INTO public.billing_allowance_deductions (organization_id, allowance_id, deduction_key, covers, amount_usd, status, period_start)
  VALUES ('org_rf_part', id1, 'usage:2026-11-23', 'usage', 250.00, 'applied', '2026-11-23T00:00:00Z');
  r := public.end_package_grant_for_payment('pi_rf2', 'refund', 150000, 200000);
  PERFORM contract_fixture.check(r->>'status' = 'ended' AND (r->>'amount_usd')::numeric = 250.00, 'S40 drawn = amount: ' || r::text);

  -- Drawn past the reduced amount at the refund: ended, with the reduced amount.
  r := public.activate_package_checkout('cs_rf3', 'org_rf_drawn', 'pilot', 200000, 'usd', 'pi_rf3', 'user_r');
  id1 := (r->>'allowance_id')::uuid;
  INSERT INTO public.billing_allowance_deductions (organization_id, allowance_id, deduction_key, covers, amount_usd, status, period_start)
  VALUES ('org_rf_drawn', id1, 'fee:2026-11-23:infrastructure', 'fee', 47.00, 'applied', '2026-11-23T00:00:00Z'),
         ('org_rf_drawn', id1, 'usage:2026-11-23', 'usage', 553.00, 'reserved', '2026-11-23T00:00:00Z');
  r := public.end_package_grant_for_payment('pi_rf3', 'refund', 100000, 200000);
  SELECT * INTO a FROM public.workspace_allowances WHERE id = id1;
  PERFORM contract_fixture.check(r->>'status' = 'ended' AND a.status = 'ended' AND a.amount_usd = 500.00
                                 AND a.ended_by = 'system:stripe_refund', 'S40 drawn past it: ' || r::text);

  -- not_found: an unknown payment, and a code activation (no Checkout session).
  r := public.end_package_grant_for_payment('pi_nope', 'refund', 100, 50000);
  PERFORM contract_fixture.check(r->>'status' = 'not_found' AND r->>'allowance_id' IS NULL, 'not_found: ' || r::text);
  INSERT INTO public.activation_fees (organization_id, stripe_payment_intent_id, source) VALUES ('org_acme', 'pi_code', 'package_code');
  r := public.end_package_grant_for_payment('pi_code', 'dispute', 0, 50000);
  PERFORM contract_fixture.check(r->>'status' = 'not_found', 'no session, not_found: ' || r::text);
  -- A zero refund, and a malformed call, change nothing.
  r := public.activate_package_checkout('cs_rf4', 'org_card', 'solo', 50000, 'usd', 'pi_rf4', 'user_r');
  PERFORM contract_fixture.check(r->>'status' = 'grant_conflict', 'a second checkout on org_card conflicts: ' || r::text);
  r := public.end_package_grant_for_payment('pi_1', 'refund', 0, 50000);
  PERFORM contract_fixture.check(r->>'status' = 'unchanged' AND (r->>'amount_usd')::numeric = 250, 'zero refund: ' || r::text);
  r := public.end_package_grant_for_payment('pi_1', 'chargeback', 0, 50000);
  PERFORM contract_fixture.check(r->>'status' = 'unchanged' AND r->>'reason' = 'invalid_request', 'unknown kind: ' || r::text);
  r := public.end_package_grant_for_payment('pi_1', 'refund', 100, 0);
  PERFORM contract_fixture.check(r->>'status' = 'unchanged' AND r->>'reason' = 'invalid_request', 'no charge amount: ' || r::text);
  PERFORM contract_fixture.check(
    (SELECT status = 'active' AND amount_usd = 250 FROM public.workspace_allowances WHERE dedupe_key = 'checkout:cs_1'),
    'org_card''s grant is untouched');
END $$;

SELECT 'Package activation contract (single session) passed.' AS result;
