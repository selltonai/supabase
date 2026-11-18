-- Migration 427's contract. Run by tests/run-backoffice-cs-agent-commercial-contract.sh on a disposable database.

-- refuses(sql, sqlstate, what): the statement must fail with exactly that error (23514 check, 23505 unique,
-- 23503 foreign key, 23502 not null).
CREATE FUNCTION pg_temp.refuses(p_sql text, p_state text, p_what text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE got text;
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN others THEN got := SQLSTATE;
  END;
  IF got IS NULL THEN RAISE EXCEPTION 'accepted: %', p_what; END IF;
  IF got <> p_state THEN RAISE EXCEPTION 'refused with % instead of %: %', got, p_state, p_what; END IF;
END $$;

-- Access: the service role only, RLS on, no policies; billing_settings untouched by 427 (applied twice).
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['workspace_plans', 'workspace_price_overrides', 'workspace_allowances', 'seat_discounts',
                           'trial_policies', 'discount_policies', 'connection_ledger', 'workspace_company_profile',
                           'cs_customer_signals', 'cs_brain_cursor'] LOOP
    IF has_table_privilege('anon', 'public.' || t, 'SELECT') OR has_table_privilege('authenticated', 'public.' || t, 'SELECT')
       OR has_table_privilege('anon', 'public.' || t, 'INSERT') OR has_table_privilege('authenticated', 'public.' || t, 'INSERT')
       OR has_table_privilege('anon', 'public.' || t, 'UPDATE') OR has_table_privilege('authenticated', 'public.' || t, 'UPDATE')
       OR has_table_privilege('anon', 'public.' || t, 'DELETE') OR has_table_privilege('authenticated', 'public.' || t, 'DELETE') THEN
      RAISE EXCEPTION 'anon/authenticated still have privileges on %', t;
    END IF;
    IF NOT has_table_privilege('service_role', 'public.' || t, 'INSERT') THEN RAISE EXCEPTION 'service_role cannot insert into %', t; END IF;
    IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = ('public.' || t)::regclass) THEN RAISE EXCEPTION 'RLS is off on %', t; END IF;
    IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = t) THEN RAISE EXCEPTION '% has a policy', t; END IF;
  END LOOP;
  IF EXISTS (SELECT * FROM public.billing_settings EXCEPT SELECT * FROM contract_fixture.billing_settings_before)
     OR EXISTS (SELECT * FROM contract_fixture.billing_settings_before EXCEPT SELECT * FROM public.billing_settings) THEN
    RAISE EXCEPTION '427 changed billing_settings';
  END IF;
  -- 422's batch_id is not re-declared.
  IF (SELECT count(*) FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'cs_recommendations' AND column_name = 'batch_id') <> 1 THEN
    RAISE EXCEPTION 'cs_recommendations.batch_id is missing or doubled';
  END IF;
END $$;

-- A browser key is refused on every table.
SET ROLE anon;
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['workspace_plans', 'workspace_price_overrides', 'workspace_allowances', 'seat_discounts',
                           'trial_policies', 'discount_policies', 'connection_ledger', 'workspace_company_profile',
                           'cs_customer_signals', 'cs_brain_cursor'] LOOP
    BEGIN
      EXECUTE format('SELECT count(*) FROM public.%I', t);
      RAISE EXCEPTION 'anon read %', t;
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  END LOOP;
END $$;
RESET ROLE;
SET ROLE authenticated;
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['workspace_plans', 'workspace_price_overrides', 'workspace_allowances', 'seat_discounts',
                           'trial_policies', 'discount_policies', 'connection_ledger', 'workspace_company_profile',
                           'cs_customer_signals', 'cs_brain_cursor'] LOOP
    BEGIN
      EXECUTE format('SELECT count(*) FROM public.%I', t);
      RAISE EXCEPTION 'authenticated read %', t;
    EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  END LOOP;
  BEGIN
    INSERT INTO public.cs_brain_cursor (environment) VALUES ('local');
    RAISE EXCEPTION 'authenticated wrote cs_brain_cursor';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;

-- The policy seed: one current row per door, caps only, no default terms.
DO $$
DECLARE p public.trial_policies%ROWTYPE;
        d public.discount_policies%ROWTYPE;
BEGIN
  IF (SELECT count(*) FROM public.trial_policies) <> 2 THEN RAISE EXCEPTION 'expected two trial policy rows'; END IF;
  FOR p IN SELECT * FROM public.trial_policies LOOP
    IF p.segment <> 'all' OR p.status <> 'current' OR p.mode <> 'manual' OR p.autonomy_enabled
       OR p.default_days IS NOT NULL OR p.default_credit_usd IS NOT NULL OR p.default_fees_waived <> '{}'::text[]
       OR p.cap_days_min <> 3 OR p.cap_days_max <> 14 OR p.cap_extensions <> 1 OR p.confirmed_by IS NULL THEN
      RAISE EXCEPTION 'bad trial policy seed: %', row_to_json(p);
    END IF;
    IF NOT ((p.door = 'web' AND p.cap_credit_usd = 100) OR (p.door = 'mobile' AND p.cap_credit_usd = 20)) THEN
      RAISE EXCEPTION 'bad trial credit cap: %', row_to_json(p);
    END IF;
  END LOOP;
  IF (SELECT count(DISTINCT door) FROM public.trial_policies) <> 2 THEN RAISE EXCEPTION 'a door is missing'; END IF;
  SELECT * INTO d FROM public.discount_policies;
  IF (SELECT count(*) FROM public.discount_policies) <> 1 OR d.door <> 'mobile' OR d.product <> 'mobile_seat'
     OR d.status <> 'current' OR d.mode <> 'manual' OR d.autonomy_enabled
     OR d.default_percent IS NOT NULL OR d.default_cycles IS NOT NULL
     OR d.cap_percent <> 50 OR d.cap_cycles <> 3 OR d.cap_months_between <> 6 THEN
    RAISE EXCEPTION 'bad discount policy seed: %', row_to_json(d);
  END IF;
END $$;

-- Trial policies: caps per door, defaults inside the caps, one current row, confirmation, no auto without terms.
DO $$
DECLARE v_id uuid;
BEGIN
  PERFORM pg_temp.refuses($q$INSERT INTO public.trial_policies (door, cap_days_min, cap_days_max, cap_credit_usd, set_by)
    VALUES ('web', 3, 14, 101, 'agent')$q$, '23514', 'a web credit cap over 100');
  PERFORM pg_temp.refuses($q$INSERT INTO public.trial_policies (door, cap_days_min, cap_days_max, cap_credit_usd, set_by)
    VALUES ('mobile', 3, 14, 21, 'agent')$q$, '23514', 'a phone credit cap over 20');
  PERFORM pg_temp.refuses($q$INSERT INTO public.trial_policies (door, cap_days_min, cap_days_max, cap_credit_usd, set_by)
    VALUES ('web', 2, 14, 50, 'agent')$q$, '23514', 'a minimum under 3 days');
  PERFORM pg_temp.refuses($q$INSERT INTO public.trial_policies (door, cap_days_min, cap_days_max, cap_credit_usd, set_by)
    VALUES ('web', 3, 15, 50, 'agent')$q$, '23514', 'a maximum over 14 days');
  PERFORM pg_temp.refuses($q$INSERT INTO public.trial_policies (door, cap_days_min, cap_days_max, cap_credit_usd, set_by)
    VALUES ('web', 10, 5, 50, 'agent')$q$, '23514', 'a minimum above the maximum');
  PERFORM pg_temp.refuses($q$INSERT INTO public.trial_policies (door, cap_days_min, cap_days_max, cap_credit_usd, set_by)
    VALUES ('tablet', 3, 14, 10, 'agent')$q$, '23514', 'an unknown door');
  PERFORM pg_temp.refuses($q$INSERT INTO public.trial_policies (door, cap_days_min, cap_days_max, cap_credit_usd, default_days, set_by)
    VALUES ('web', 3, 10, 50, 12, 'agent')$q$, '23514', 'default days above the cap');
  PERFORM pg_temp.refuses($q$INSERT INTO public.trial_policies (door, cap_days_min, cap_days_max, cap_credit_usd, default_credit_usd, set_by)
    VALUES ('mobile', 3, 14, 10, 15, 'agent')$q$, '23514', 'a default credit above the cap');
  PERFORM pg_temp.refuses($q$INSERT INTO public.trial_policies (door, cap_days_min, cap_days_max, cap_credit_usd, cap_extensions, set_by)
    VALUES ('web', 3, 14, 50, 2, 'agent')$q$, '23514', 'two extensions');
  PERFORM pg_temp.refuses($q$INSERT INTO public.trial_policies (door, cap_days_min, cap_days_max, cap_credit_usd, mode, set_by)
    VALUES ('web', 3, 14, 50, 'auto', 'agent')$q$, '23514', 'auto mode without default terms');
  PERFORM pg_temp.refuses($q$INSERT INTO public.trial_policies (door, cap_days_min, cap_days_max, cap_credit_usd, autonomy_enabled, set_by)
    VALUES ('web', 3, 14, 50, true, 'agent')$q$, '23514', 'autonomy without default terms');
  -- The agent proposes a default (a proposal needs no confirmation); confirming it while the seed is current is refused.
  INSERT INTO public.trial_policies (door, cap_days_min, cap_days_max, cap_credit_usd, default_days, default_credit_usd,
                                     set_by, reason, dedupe_key)
    VALUES ('mobile', 3, 14, 20, 7, 5, 'agent', 'proposal', 'trial_policy:mobile:all:1') RETURNING id INTO v_id;
  PERFORM pg_temp.refuses(format($q$UPDATE public.trial_policies SET status = 'current' WHERE id = %L$q$, v_id),
    '23514', 'current without a confirmation');
  PERFORM pg_temp.refuses(format($q$UPDATE public.trial_policies SET status = 'current', confirmed_by = 'staff@example.com',
    confirmed_at = now() WHERE id = %L$q$, v_id), '23505', 'a second current row for the door and segment');
  PERFORM pg_temp.refuses($q$INSERT INTO public.trial_policies (door, cap_days_min, cap_days_max, cap_credit_usd, set_by, dedupe_key)
    VALUES ('mobile', 3, 14, 20, 'agent', 'trial_policy:mobile:all:1')$q$, '23505', 'a second proposal with the same key');
  -- Superseding the seed, then confirming the proposal: the history keeps both rows.
  UPDATE public.trial_policies SET status = 'superseded' WHERE door = 'mobile' AND status = 'current';
  UPDATE public.trial_policies SET status = 'current', mode = 'auto', confirmed_by = 'staff@example.com', confirmed_at = now(),
    supersedes_id = (SELECT id FROM public.trial_policies WHERE door = 'mobile' AND status = 'superseded')
    WHERE id = v_id;
  IF (SELECT count(*) FROM public.trial_policies WHERE door = 'mobile') <> 2 THEN RAISE EXCEPTION 'the history lost a row'; END IF;
  -- Another segment has its own current row.
  INSERT INTO public.trial_policies (door, segment, status, cap_days_min, cap_days_max, cap_credit_usd, set_by, confirmed_by, confirmed_at)
    VALUES ('web', 'saas_50_plus', 'current', 3, 14, 100, 'staff@example.com', 'staff@example.com', now());
END $$;

-- Discount policies: caps, defaults inside the caps, one current row per door, segment and product.
DO $$ BEGIN
  PERFORM pg_temp.refuses($q$INSERT INTO public.discount_policies (door, product, cap_percent, cap_cycles, cap_months_between, set_by)
    VALUES ('mobile', 'mobile_seat', 60, 3, 6, 'agent')$q$, '23514', 'a cap over 50 percent');
  PERFORM pg_temp.refuses($q$INSERT INTO public.discount_policies (door, product, cap_percent, cap_cycles, cap_months_between, set_by)
    VALUES ('mobile', 'mobile_seat', 50, 4, 6, 'agent')$q$, '23514', 'a cap over 3 cycles');
  PERFORM pg_temp.refuses($q$INSERT INTO public.discount_policies (door, product, cap_percent, cap_cycles, cap_months_between, set_by)
    VALUES ('mobile', 'mobile_seat', 50, 3, 5, 'agent')$q$, '23514', 'less than 6 months between discounts');
  PERFORM pg_temp.refuses($q$INSERT INTO public.discount_policies (door, product, cap_percent, cap_cycles, cap_months_between, default_percent, set_by)
    VALUES ('mobile', 'mobile_seat', 40, 3, 6, 45, 'agent')$q$, '23514', 'a default percent above the cap');
  PERFORM pg_temp.refuses($q$INSERT INTO public.discount_policies (door, product, cap_percent, cap_cycles, cap_months_between, default_cycles, set_by)
    VALUES ('mobile', 'mobile_seat', 50, 2, 6, 3, 'agent')$q$, '23514', 'default cycles above the cap');
  PERFORM pg_temp.refuses($q$INSERT INTO public.discount_policies (door, product, cap_percent, cap_cycles, cap_months_between, mode, set_by)
    VALUES ('mobile', 'mobile_seat', 50, 3, 6, 'auto', 'agent')$q$, '23514', 'auto mode without default terms');
  PERFORM pg_temp.refuses($q$INSERT INTO public.discount_policies (door, product, cap_percent, cap_cycles, cap_months_between, set_by)
    VALUES ('mobile', 'usage', 50, 3, 6, 'agent')$q$, '23514', 'a discount on usage');
  PERFORM pg_temp.refuses($q$INSERT INTO public.discount_policies (door, product, status, cap_percent, cap_cycles, cap_months_between, set_by)
    VALUES ('mobile', 'mobile_seat', 'current', 50, 3, 6, 'agent')$q$, '23514', 'current without a confirmation');
  PERFORM pg_temp.refuses($q$INSERT INTO public.discount_policies (door, product, status, cap_percent, cap_cycles, cap_months_between, set_by, confirmed_by, confirmed_at)
    VALUES ('mobile', 'mobile_seat', 'current', 50, 3, 6, 'agent', 'staff@example.com', now())$q$, '23505', 'a second current row');
  INSERT INTO public.discount_policies (door, product, cap_percent, cap_cycles, cap_months_between, default_percent, default_cycles, set_by)
    VALUES ('mobile', 'mobile_seat', 50, 3, 6, 50, 3, 'agent');
END $$;

-- Plans: the approval guard, one active plan, a pilot's term, the conversion link, numbers never negative.
DO $$
DECLARE v_pilot uuid; v_deploy uuid;
BEGIN
  INSERT INTO public.workspace_plans (organization_id, plan, fee_usd, included_usage_usd, seats_included, created_by)
    VALUES ('org_a', 'pilot', 2000, 500, 3, 'staff@example.com') RETURNING id INTO v_pilot;
  IF (SELECT status FROM public.workspace_plans WHERE id = v_pilot) <> 'proposed'
     OR (SELECT success_criteria FROM public.workspace_plans WHERE id = v_pilot) <> '{}'::jsonb THEN
    RAISE EXCEPTION 'bad plan defaults';
  END IF;
  PERFORM pg_temp.refuses(format($q$UPDATE public.workspace_plans SET status = 'active', term_start = '2026-11-12',
    term_end = '2026-12-24' WHERE id = %L$q$, v_pilot), '23514', 'a plan active without an approver');
  PERFORM pg_temp.refuses(format($q$UPDATE public.workspace_plans SET status = 'active', approved_by = 'boss@example.com',
    approved_at = now() WHERE id = %L$q$, v_pilot), '23514', 'a pilot active without its term');
  PERFORM pg_temp.refuses(format($q$UPDATE public.workspace_plans SET term_start = '2026-12-24', term_end = '2026-11-12'
    WHERE id = %L$q$, v_pilot), '23514', 'a term that ends before it starts');
  UPDATE public.workspace_plans SET status = 'active', approved_by = 'boss@example.com', approved_at = now(),
    term_start = '2026-11-12', term_end = '2026-12-24', success_criteria = '{"meetings_booked": 8}'::jsonb WHERE id = v_pilot;
  PERFORM pg_temp.refuses($q$INSERT INTO public.workspace_plans (organization_id, plan, status, created_by, approved_by, approved_at)
    VALUES ('org_a', 'self_serve', 'active', 'staff@example.com', 'boss@example.com', now())$q$, '23505', 'a second active plan');
  PERFORM pg_temp.refuses($q$INSERT INTO public.workspace_plans (organization_id, plan, created_by)
    VALUES ('org_a', 'enterprise', 'staff@example.com')$q$, '23514', 'an unknown plan');
  PERFORM pg_temp.refuses($q$INSERT INTO public.workspace_plans (organization_id, plan, fee_usd, created_by)
    VALUES ('org_a', 'deployment', -1, 'staff@example.com')$q$, '23514', 'a negative fee');
  PERFORM pg_temp.refuses($q$INSERT INTO public.workspace_plans (organization_id, plan, created_by)
    VALUES ('org_unknown', 'pilot', 'staff@example.com')$q$, '23503', 'a plan for an unknown organization');
  PERFORM pg_temp.refuses(format($q$UPDATE public.workspace_plans SET status = 'converted' WHERE id = %L$q$, v_pilot),
    '23514', 'converted without the plan it became');
  PERFORM pg_temp.refuses(format($q$UPDATE public.workspace_plans SET status = 'converted', converted_to = id WHERE id = %L$q$, v_pilot),
    '23514', 'a plan converted into itself');
  -- The pilot converts into a deployment, which then becomes the active plan.
  INSERT INTO public.workspace_plans (organization_id, plan, fee_usd, created_by, dedupe_key)
    VALUES ('org_a', 'deployment', 5000, 'staff@example.com', 'plan:org_a:deployment') RETURNING id INTO v_deploy;
  UPDATE public.workspace_plans SET status = 'converted', converted_to = v_deploy WHERE id = v_pilot;
  UPDATE public.workspace_plans SET status = 'active', approved_by = 'boss@example.com', approved_at = now() WHERE id = v_deploy;
  PERFORM pg_temp.refuses($q$INSERT INTO public.workspace_plans (organization_id, plan, created_by, dedupe_key)
    VALUES ('org_a', 'deployment', 'staff@example.com', 'plan:org_a:deployment')$q$, '23505', 'a second plan with the same key');
  PERFORM pg_temp.refuses(format($q$DELETE FROM public.workspace_plans WHERE id = %L$q$, v_deploy),
    '23503', 'deleting the plan a pilot converted into');
END $$;

-- Price overrides: exactly one of value and percent, the approval guard, the window, the item key.
DO $$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.workspace_price_overrides (organization_id, item, value_usd, reason, set_by)
    VALUES ('org_a', 'seat_web_4w_usd', 15, 'existing customer', 'staff@example.com') RETURNING id INTO v_id;
  INSERT INTO public.workspace_price_overrides (organization_id, item, percent, user_id, reason, set_by, status, approved_by, approved_at)
    VALUES ('org_a', 'seat_mobile_4w_usd', 25, 'user_1', 'per-person seat', 'staff@example.com', 'active', 'boss@example.com', now());
  PERFORM pg_temp.refuses($q$INSERT INTO public.workspace_price_overrides (organization_id, item, value_usd, percent, reason, set_by)
    VALUES ('org_a', 'seat_web_4w_usd', 10, 10, 'both', 'staff@example.com')$q$, '23514', 'both a value and a percent');
  PERFORM pg_temp.refuses($q$INSERT INTO public.workspace_price_overrides (organization_id, item, reason, set_by)
    VALUES ('org_a', 'seat_web_4w_usd', 'neither', 'staff@example.com')$q$, '23514', 'neither a value nor a percent');
  PERFORM pg_temp.refuses($q$INSERT INTO public.workspace_price_overrides (organization_id, item, percent, reason, set_by)
    VALUES ('org_a', 'seat_web_4w_usd', 101, 'x', 'staff@example.com')$q$, '23514', 'a percent over 100');
  PERFORM pg_temp.refuses($q$INSERT INTO public.workspace_price_overrides (organization_id, item, value_usd, reason, set_by)
    VALUES ('org_a', 'seat_web_4w_usd', -1, 'x', 'staff@example.com')$q$, '23514', 'a negative price');
  PERFORM pg_temp.refuses($q$INSERT INTO public.workspace_price_overrides (organization_id, item, value_usd, reason, set_by)
    VALUES ('org_a', 'Seat Web', 10, 'x', 'staff@example.com')$q$, '23514', 'an item that is not a settings key');
  PERFORM pg_temp.refuses($q$INSERT INTO public.workspace_price_overrides (organization_id, item, value_usd, reason, set_by)
    VALUES ('org_a', 'seat_web_4w_usd', 10, '', 'staff@example.com')$q$, '23514', 'an empty reason');
  PERFORM pg_temp.refuses($q$INSERT INTO public.workspace_price_overrides (organization_id, item, value_usd, reason, set_by, starts_at, ends_at)
    VALUES ('org_a', 'seat_web_4w_usd', 10, 'x', 'staff@example.com', '2026-12-01', '2026-11-01')$q$, '23514', 'a window that ends before it starts');
  PERFORM pg_temp.refuses(format($q$UPDATE public.workspace_price_overrides SET status = 'active' WHERE id = %L$q$, v_id),
    '23514', 'an override active without an approver');
  PERFORM pg_temp.refuses(format($q$UPDATE public.workspace_price_overrides SET status = 'active', approved_by = 'boss@example.com'
    WHERE id = %L$q$, v_id), '23514', 'an override active without an approval time');
  UPDATE public.workspace_price_overrides SET status = 'active', approved_by = 'boss@example.com', approved_at = now() WHERE id = v_id;
  PERFORM pg_temp.refuses(format($q$UPDATE public.workspace_price_overrides SET status = 'ended' WHERE id = %L$q$, v_id),
    '23514', 'ended without who and when');
  UPDATE public.workspace_price_overrides SET status = 'ended', ended_by = 'staff@example.com', ended_at = now() WHERE id = v_id;
  -- A scheduled change is a second active row with a later start; both may be active.
  INSERT INTO public.workspace_price_overrides (organization_id, item, value_usd, reason, set_by, status, approved_by, approved_at, starts_at, dedupe_key)
    VALUES ('org_a', 'infrastructure_fee_4w_usd', 30, 'x', 'staff@example.com', 'active', 'boss@example.com', now(), now(), 'po:1'),
           ('org_a', 'infrastructure_fee_4w_usd', 25, 'x', 'staff@example.com', 'active', 'boss@example.com', now(), now() + interval '28 days', 'po:2');
  PERFORM pg_temp.refuses($q$INSERT INTO public.workspace_price_overrides (organization_id, item, value_usd, reason, set_by, dedupe_key)
    VALUES ('org_a', 'infrastructure_fee_4w_usd', 20, 'x', 'staff@example.com', 'po:1')$q$, '23505', 'a second override with the same key');
END $$;

-- Allowances: an amount, an end, or both; the approval guard; prepaid needs an invoice; one active per workspace.
DO $$
DECLARE v_id uuid;
BEGIN
  PERFORM pg_temp.refuses($q$INSERT INTO public.workspace_allowances (organization_id, kind, reason, set_by)
    VALUES ('org_a', 'trial', 'x', 'agent')$q$, '23514', 'an allowance with neither an amount nor an end');
  INSERT INTO public.workspace_allowances (organization_id, kind, amount_usd, reason, set_by)
    VALUES ('org_a', 'goodwill', 40, 'amount only', 'staff@example.com');
  INSERT INTO public.workspace_allowances (organization_id, kind, expires_at, reason, set_by)
    VALUES ('org_a', 'trial', now() + interval '7 days', 'time only', 'staff@example.com');
  INSERT INTO public.workspace_allowances (organization_id, kind, amount_usd, expires_at, reason, set_by)
    VALUES ('org_a', 'trial', 40, now() + interval '7 days', 'both', 'agent') RETURNING id INTO v_id;
  IF (SELECT row(status, on_end, spent_usd, last_alert_percent, claimed_at IS NULL, invoiced)::text
      FROM public.workspace_allowances WHERE id = v_id) <> '(proposed,pause,0.00,0,t,f)' THEN
    RAISE EXCEPTION 'bad allowance defaults';
  END IF;
  PERFORM pg_temp.refuses($q$INSERT INTO public.workspace_allowances (organization_id, kind, amount_usd, reason, set_by)
    VALUES ('org_a', 'refund', 10, 'x', 'agent')$q$, '23514', 'an unknown kind');
  PERFORM pg_temp.refuses($q$INSERT INTO public.workspace_allowances (organization_id, kind, amount_usd, on_end, reason, set_by)
    VALUES ('org_a', 'trial', 10, 'delete', 'x', 'agent')$q$, '23514', 'an unknown on_end');
  PERFORM pg_temp.refuses($q$INSERT INTO public.workspace_allowances (organization_id, kind, amount_usd, reason, set_by)
    VALUES ('org_a', 'trial', 0, 'x', 'agent')$q$, '23514', 'a zero amount');
  PERFORM pg_temp.refuses($q$INSERT INTO public.workspace_allowances (organization_id, kind, starts_at, expires_at, reason, set_by)
    VALUES ('org_a', 'trial', now(), now() - interval '1 day', 'x', 'agent')$q$, '23514', 'an end before the start');
  PERFORM pg_temp.refuses(format($q$UPDATE public.workspace_allowances SET status = 'active' WHERE id = %L$q$, v_id),
    '23514', 'an allowance active without an approver');
  UPDATE public.workspace_allowances SET status = 'active', approved_by = 'boss@example.com', approved_at = now() WHERE id = v_id;
  PERFORM pg_temp.refuses($q$INSERT INTO public.workspace_allowances (organization_id, kind, amount_usd, reason, set_by, status, approved_by, approved_at)
    VALUES ('org_a', 'goodwill', 10, 'x', 'staff@example.com', 'active', 'boss@example.com', now())$q$, '23505', 'a second active allowance');
  -- The 15-minute job: claims, computes, raises an alert once, then ends the row.
  UPDATE public.workspace_allowances SET claimed_at = now(), spent_usd = 21.50, last_computed_at = now(), last_alert_percent = 50
    WHERE id = v_id AND (claimed_at IS NULL OR claimed_at < now() - interval '10 minutes');
  PERFORM pg_temp.refuses(format($q$UPDATE public.workspace_allowances SET last_alert_percent = 60 WHERE id = %L$q$, v_id),
    '23514', 'an alert threshold that is not 50, 80 or 100');
  PERFORM pg_temp.refuses(format($q$UPDATE public.workspace_allowances SET spent_usd = -1 WHERE id = %L$q$, v_id),
    '23514', 'a negative spend');
  PERFORM pg_temp.refuses(format($q$UPDATE public.workspace_allowances SET status = 'spent' WHERE id = %L$q$, v_id),
    '23514', 'spent without who and when');
  UPDATE public.workspace_allowances SET status = 'spent', ended_by = 'allowance_job', ended_at = now(), claimed_at = NULL WHERE id = v_id;
  PERFORM pg_temp.refuses($q$INSERT INTO public.workspace_allowances (organization_id, kind, expires_at, reason, set_by, status, approved_by, approved_at, ended_by, ended_at)
    VALUES ('org_c', 'trial', now() + interval '1 day', 'x', 'agent', 'spent', 'boss@example.com', now(), 'allowance_job', now())$q$,
    '23514', 'spent with no amount');
  PERFORM pg_temp.refuses($q$INSERT INTO public.workspace_allowances (organization_id, kind, amount_usd, reason, set_by, status, approved_by, approved_at, ended_by, ended_at)
    VALUES ('org_c', 'trial', 10, 'x', 'agent', 'expired', 'boss@example.com', now(), 'allowance_job', now())$q$,
    '23514', 'expired with no end time');
  -- Prepaid: only with a Stripe invoice id or invoiced.
  PERFORM pg_temp.refuses($q$INSERT INTO public.workspace_allowances (organization_id, kind, amount_usd, reason, set_by, status, approved_by, approved_at)
    VALUES ('org_b', 'prepaid', 2000, 'x', 'staff@example.com', 'active', 'boss@example.com', now())$q$, '23514', 'prepaid without an invoice');
  INSERT INTO public.workspace_allowances (organization_id, kind, amount_usd, reason, set_by)
    VALUES ('org_b', 'prepaid', 2000, 'proposal', 'staff@example.com');
  INSERT INTO public.workspace_allowances (organization_id, kind, amount_usd, reason, set_by, status, approved_by, approved_at,
                                          stripe_invoice_id, plan_id, dedupe_key)
    VALUES ('org_c', 'prepaid', 2000, 'x', 'staff@example.com', 'active', 'boss@example.com', now(), 'in_test_1',
            (SELECT id FROM public.workspace_plans WHERE plan = 'deployment' AND status = 'active'), 'allowance:org_c:1');
  PERFORM pg_temp.refuses($q$INSERT INTO public.workspace_allowances (organization_id, kind, amount_usd, reason, set_by, dedupe_key)
    VALUES ('org_c', 'goodwill', 10, 'x', 'staff@example.com', 'allowance:org_c:1')$q$, '23505', 'a second allowance with the same key');
  INSERT INTO public.workspace_allowances (organization_id, kind, amount_usd, reason, set_by, status, approved_by, approved_at, invoiced)
    VALUES ('org_b', 'prepaid', 1000, 'x', 'staff@example.com', 'active', 'boss@example.com', now(), true);
END $$;

-- Seat discounts: within the caps, the agent always time-boxes, never stacked, ended with a known reason.
DO $$
DECLARE v_id uuid;
BEGIN
  PERFORM pg_temp.refuses($q$INSERT INTO public.seat_discounts (organization_id, product, percent, cycles, reason, set_by)
    VALUES ('org_a', 'mobile_seat', 51, 3, 'x', 'agent')$q$, '23514', 'a discount over 50 percent');
  PERFORM pg_temp.refuses($q$INSERT INTO public.seat_discounts (organization_id, product, percent, cycles, reason, set_by)
    VALUES ('org_a', 'mobile_seat', 0, 3, 'x', 'agent')$q$, '23514', 'a zero discount');
  PERFORM pg_temp.refuses($q$INSERT INTO public.seat_discounts (organization_id, product, percent, cycles, reason, set_by)
    VALUES ('org_a', 'mobile_seat', 50, 4, 'x', 'agent')$q$, '23514', 'more than 3 cycles');
  PERFORM pg_temp.refuses($q$INSERT INTO public.seat_discounts (organization_id, product, percent, reason, set_by)
    VALUES ('org_a', 'mobile_seat', 50, 'x', 'agent')$q$, '23514', 'an agent discount without a cycle count');
  PERFORM pg_temp.refuses($q$INSERT INTO public.seat_discounts (organization_id, product, percent, cycles, reason, set_by)
    VALUES ('org_a', 'usage', 50, 3, 'x', 'agent')$q$, '23514', 'a discount on usage');
  INSERT INTO public.seat_discounts (organization_id, product, percent, cycles, reason, set_by)
    VALUES ('org_a', 'mobile_seat', 50, 3, 'phone signup', 'agent') RETURNING id INTO v_id;
  -- Staff may leave the cycle count open (until removed).
  INSERT INTO public.seat_discounts (organization_id, product, percent, reason, set_by, user_id)
    VALUES ('org_a', 'web_seat', 37.5, 'existing customer', 'staff@example.com', 'user_1');
  PERFORM pg_temp.refuses(format($q$UPDATE public.seat_discounts SET status = 'active' WHERE id = %L$q$, v_id),
    '23514', 'a discount active without an approver');
  UPDATE public.seat_discounts SET status = 'active', approved_by = 'boss@example.com', approved_at = now() WHERE id = v_id;
  PERFORM pg_temp.refuses($q$INSERT INTO public.seat_discounts (organization_id, product, percent, cycles, reason, set_by, status, approved_by, approved_at)
    VALUES ('org_a', 'mobile_seat', 20, 1, 'x', 'agent', 'active', 'boss@example.com', now())$q$, '23505', 'two active workspace discounts on one product');
  -- A person's discount next to the workspace's is allowed; two for the same person are not.
  INSERT INTO public.seat_discounts (organization_id, product, percent, cycles, reason, set_by, user_id, status, approved_by, approved_at)
    VALUES ('org_a', 'mobile_seat', 50, 2, 'second person', 'agent', 'user_2', 'active', 'boss@example.com', now());
  PERFORM pg_temp.refuses($q$INSERT INTO public.seat_discounts (organization_id, product, percent, cycles, reason, set_by, user_id, status, approved_by, approved_at)
    VALUES ('org_a', 'mobile_seat', 10, 1, 'x', 'agent', 'user_2', 'active', 'boss@example.com', now())$q$, '23505', 'two active discounts for one person');
  PERFORM pg_temp.refuses(format($q$UPDATE public.seat_discounts SET status = 'ended', ended_by = 'refund', ended_at = now() WHERE id = %L$q$, v_id),
    '23514', 'an unknown end reason');
  PERFORM pg_temp.refuses(format($q$UPDATE public.seat_discounts SET status = 'ended' WHERE id = %L$q$, v_id),
    '23514', 'ended without a reason and time');
  UPDATE public.seat_discounts SET status = 'ended', ended_by = 'web_activation', ended_at = now() WHERE id = v_id;
  INSERT INTO public.seat_discounts (organization_id, product, percent, cycles, reason, set_by, status, approved_by, approved_at, dedupe_key)
    VALUES ('org_a', 'mobile_seat', 25, 1, 'x', 'agent', 'active', 'boss@example.com', now(), 'discount:org_a:2026H2');
  PERFORM pg_temp.refuses($q$INSERT INTO public.seat_discounts (organization_id, product, percent, cycles, reason, set_by, dedupe_key)
    VALUES ('org_a', 'mobile_seat', 25, 1, 'x', 'agent', 'discount:org_a:2026H2')$q$, '23505', 'a second discount with the same key');
END $$;

-- Connection ledger: the nightly upsert key, one open period per account, kept when the workspace goes.
DO $$ BEGIN
  INSERT INTO public.connection_ledger (organization_id, user_id, provider, account_id, kind, source, connected_at, monthly_cost_usd)
    VALUES ('org_b', 'user_3', 'unipile', 'acc_1', 'linkedin', 'web', '2026-10-01', 5.5);
  -- The same period again is a no-op through the upsert key; a second open period for the account is refused.
  INSERT INTO public.connection_ledger (organization_id, provider, account_id, kind, source, connected_at)
    VALUES ('org_b', 'unipile', 'acc_1', 'linkedin', 'web', '2026-10-01')
    ON CONFLICT (provider, account_id, connected_at) DO NOTHING;
  PERFORM pg_temp.refuses($q$INSERT INTO public.connection_ledger (organization_id, provider, account_id, kind, source, connected_at)
    VALUES ('org_b', 'unipile', 'acc_1', 'linkedin', 'web', '2026-11-01')$q$, '23505', 'a second open period while one is open');
  IF (SELECT count(*) FROM public.connection_ledger WHERE account_id = 'acc_1') <> 1 THEN
    RAISE EXCEPTION 'the upsert key or the open-period guard failed';
  END IF;
  UPDATE public.connection_ledger SET disconnected_at = '2026-10-20' WHERE account_id = 'acc_1';
  INSERT INTO public.connection_ledger (organization_id, provider, account_id, kind, source, connected_at)
    VALUES ('org_b', 'unipile', 'acc_1', 'linkedin', 'web', '2026-11-01');
  PERFORM pg_temp.refuses($q$INSERT INTO public.connection_ledger (organization_id, provider, account_id, kind, source, connected_at)
    VALUES ('org_b', 'unipile', 'acc_1', 'linkedin', 'web', '2026-11-05')$q$, '23505', 'a second open period for an account');
  PERFORM pg_temp.refuses($q$INSERT INTO public.connection_ledger (organization_id, provider, account_id, kind, source, connected_at)
    VALUES ('org_b', 'unipile', 'acc_2', 'whatsapp', 'web', now())$q$, '23514', 'an unknown kind');
  PERFORM pg_temp.refuses($q$INSERT INTO public.connection_ledger (organization_id, provider, account_id, kind, source, connected_at)
    VALUES ('org_b', 'unipile', 'acc_2', 'phone', 'desktop', now())$q$, '23514', 'an unknown source');
  PERFORM pg_temp.refuses($q$INSERT INTO public.connection_ledger (organization_id, provider, account_id, kind, source, connected_at, disconnected_at)
    VALUES ('org_b', 'gmail_api', 'box@example.com', 'mailbox', 'web', '2026-11-02', '2026-11-01')$q$, '23514', 'disconnected before connected');
  PERFORM pg_temp.refuses($q$INSERT INTO public.connection_ledger (organization_id, provider, account_id, kind, source, connected_at, monthly_cost_usd)
    VALUES ('org_b', 'gmail_api', 'box@example.com', 'mailbox', 'web', now(), -1)$q$, '23514', 'a negative cost');
  PERFORM pg_temp.refuses($q$INSERT INTO public.connection_ledger (organization_id, provider, account_id, kind, source, connected_at, corrected_by)
    VALUES ('org_b', 'gmail_api', 'box@example.com', 'mailbox', 'web', now(), 'staff@example.com')$q$, '23514', 'a correction without its time');
END $$;

-- Company profile and signals.
DO $$
DECLARE v_profile uuid; v_rec uuid;
BEGIN
  INSERT INTO public.workspace_company_profile (organization_id, domain, brain_company_id, source)
    VALUES ('org_a', 'acme.example', 101, 'brain_enrich') RETURNING id INTO v_profile;
  IF NOT (SELECT watch AND relation = 'own' AND profile = '{}'::jsonb AND signals = '[]'::jsonb AND fetched_at IS NULL
          FROM public.workspace_company_profile WHERE id = v_profile) THEN
    RAISE EXCEPTION 'bad profile defaults';
  END IF;
  PERFORM pg_temp.refuses($q$INSERT INTO public.workspace_company_profile (organization_id, domain, relation)
    VALUES ('org_a', 'acme.example', 'parent')$q$, '23505', 'the same domain twice for a workspace');
  PERFORM pg_temp.refuses($q$INSERT INTO public.workspace_company_profile (organization_id, domain)
    VALUES ('org_a', 'other.example')$q$, '23505', 'a second own company');
  PERFORM pg_temp.refuses($q$INSERT INTO public.workspace_company_profile (organization_id, domain, relation)
    VALUES ('org_a', 'Acme.Example', 'brand')$q$, '23514', 'a domain not in lower case');
  PERFORM pg_temp.refuses($q$INSERT INTO public.workspace_company_profile (organization_id, domain, relation)
    VALUES ('org_a', 'localhost', 'brand')$q$, '23514', 'a domain without a dot');
  PERFORM pg_temp.refuses($q$INSERT INTO public.workspace_company_profile (organization_id, domain, relation)
    VALUES ('org_a', 'x.example', 'competitor')$q$, '23514', 'an unknown relation');
  INSERT INTO public.workspace_company_profile (organization_id, domain, relation, watch, watch_reason)
    VALUES ('org_a', 'acme-parent.example', 'parent', true, 'parent company');
  -- The same company may be watched by another workspace.
  INSERT INTO public.workspace_company_profile (organization_id, domain) VALUES ('org_c', 'acme.example');

  INSERT INTO public.cs_recommendations (organization_id, kind) VALUES ('org_a', 'note') RETURNING id INTO v_rec;
  INSERT INTO public.cs_customer_signals (organization_id, brain_signal_id, company_profile_id, type, occurred_at, summary, recommendation_id)
    VALUES ('org_a', 9001, v_profile, 'hiring', now(), 'Hiring three SDRs', v_rec);
  IF (SELECT row(status, grade IS NULL, payload, people)::text FROM public.cs_customer_signals WHERE brain_signal_id = 9001)
     <> '(new,t,{},[])' THEN
    RAISE EXCEPTION 'bad signal defaults';
  END IF;
  PERFORM pg_temp.refuses($q$INSERT INTO public.cs_customer_signals (organization_id, brain_signal_id, type)
    VALUES ('org_c', 9001, 'hiring')$q$, '23505', 'a Brain signal stored twice');
  INSERT INTO public.cs_customer_signals (organization_id, brain_signal_id, type) VALUES ('org_a', 9001, 'hiring')
    ON CONFLICT (brain_signal_id) DO NOTHING;
  PERFORM pg_temp.refuses($q$UPDATE public.cs_customer_signals SET grade = 'great' WHERE brain_signal_id = 9001$q$,
    '23514', 'an unknown grade');
  PERFORM pg_temp.refuses($q$UPDATE public.cs_customer_signals SET status = 'archived' WHERE brain_signal_id = 9001$q$,
    '23514', 'an unknown status');
  PERFORM pg_temp.refuses($q$UPDATE public.cs_customer_signals SET status = 'acted' WHERE brain_signal_id = 9001$q$,
    '23514', 'acted on without who and when');
  UPDATE public.cs_customer_signals SET grade = 'expansion', status = 'acted', handled_by = 'staff@example.com', handled_at = now()
    WHERE brain_signal_id = 9001;
  -- Deleting the proposal or the profile keeps the signal.
  DELETE FROM public.cs_recommendations WHERE id = v_rec;
  DELETE FROM public.workspace_company_profile WHERE id = v_profile;
  IF (SELECT row(recommendation_id IS NULL, company_profile_id IS NULL)::text FROM public.cs_customer_signals
      WHERE brain_signal_id = 9001) <> '(t,t)' THEN
    RAISE EXCEPTION 'the signal kept a deleted proposal or profile';
  END IF;

  -- The cursor: one row per environment.
  INSERT INTO public.cs_brain_cursor (environment) VALUES ('local');
  PERFORM pg_temp.refuses($q$INSERT INTO public.cs_brain_cursor (environment) VALUES ('local')$q$, '23505', 'a second cursor for an environment');
  UPDATE public.cs_brain_cursor SET next_after = 'opaque', last_polled_at = now() WHERE environment = 'local';
END $$;

-- updated_at moves on update (now() is fixed inside one transaction, so start from an old value).
DO $$ BEGIN
  ALTER TABLE public.workspace_allowances DISABLE TRIGGER update_workspace_allowances_updated_at;
  UPDATE public.workspace_allowances SET updated_at = '2020-01-01' WHERE organization_id = 'org_a';
  ALTER TABLE public.workspace_allowances ENABLE TRIGGER update_workspace_allowances_updated_at;
  UPDATE public.workspace_allowances SET last_computed_at = now() WHERE organization_id = 'org_a';
  IF EXISTS (SELECT 1 FROM public.workspace_allowances WHERE organization_id = 'org_a' AND updated_at < '2021-01-01') THEN
    RAISE EXCEPTION 'updated_at did not move';
  END IF;
  IF (SELECT count(*) FROM pg_trigger WHERE tgname LIKE 'update\_%\_updated\_at' AND NOT tgisinternal
        AND tgrelid::regclass::text IN ('workspace_plans', 'workspace_price_overrides', 'workspace_allowances', 'seat_discounts',
          'trial_policies', 'discount_policies', 'connection_ledger', 'workspace_company_profile', 'cs_customer_signals',
          'cs_brain_cursor')) <> 10 THEN
    RAISE EXCEPTION 'an updated_at trigger is missing or doubled';
  END IF;
END $$;

-- Deleting a workspace deletes its commercial rows; its connection periods stay, without the workspace.
DO $$ BEGIN
  DELETE FROM public.organization WHERE id IN ('org_a', 'org_b');
  IF EXISTS (SELECT 1 FROM public.workspace_plans WHERE organization_id IN ('org_a', 'org_b'))
     OR EXISTS (SELECT 1 FROM public.workspace_price_overrides WHERE organization_id IN ('org_a', 'org_b'))
     OR EXISTS (SELECT 1 FROM public.workspace_allowances WHERE organization_id IN ('org_a', 'org_b'))
     OR EXISTS (SELECT 1 FROM public.seat_discounts WHERE organization_id IN ('org_a', 'org_b'))
     OR EXISTS (SELECT 1 FROM public.workspace_company_profile WHERE organization_id IN ('org_a', 'org_b'))
     OR EXISTS (SELECT 1 FROM public.cs_customer_signals WHERE organization_id IN ('org_a', 'org_b')) THEN
    RAISE EXCEPTION 'cascade failed';
  END IF;
  -- org_c's allowance pointed at org_a's deployment plan: it stays, without the plan.
  IF (SELECT plan_id FROM public.workspace_allowances WHERE organization_id = 'org_c' AND kind = 'prepaid') IS NOT NULL THEN
    RAISE EXCEPTION 'an allowance kept a deleted plan';
  END IF;
  IF (SELECT count(*) FROM public.connection_ledger WHERE organization_id IS NULL AND account_id = 'acc_1') <> 2 THEN
    RAISE EXCEPTION 'the deleted workspace''s connection periods did not stay';
  END IF;
  -- The policies are not per workspace and stay.
  IF (SELECT count(*) FROM public.trial_policies) < 2 THEN RAISE EXCEPTION 'a policy row went with a workspace'; END IF;
END $$;
SELECT 'backoffice cs agent commercial contract passed' AS result;
