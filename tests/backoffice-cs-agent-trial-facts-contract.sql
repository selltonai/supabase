-- Migration 432's contract. Run by tests/run-backoffice-cs-agent-trial-facts-contract.sh on a disposable database, in
-- one transaction (now() is the same instant in the fixtures and in both functions). Its fixtures are removed at the
-- end, so 423's own contract can run on the same database after the rollback.

CREATE FUNCTION pg_temp.cs_keys(j jsonb) RETURNS text[] LANGUAGE sql AS $$
  SELECT coalesce(array_agg(k ORDER BY k), '{}'::text[]) FROM jsonb_object_keys(j) k
$$;
CREATE FUNCTION pg_temp.cs_sorted(a text[]) RETURNS text[] LANGUAGE sql AS $$
  SELECT array_agg(x ORDER BY x) FROM unnest(a) x
$$;

-- The shape: 423's signatures, results, volatility, security and grants. -------------------------------------------
DO $$
DECLARE p record;
BEGIN
  FOR p IN
    SELECT c.signature, f.oid, f.provolatile, f.prosecdef, f.proconfig, pg_get_function_result(f.oid) AS result
    FROM contract_432.functions_423 c
    JOIN pg_proc f ON f.oid = to_regprocedure(c.signature)
  LOOP
    IF p.provolatile <> 's' OR p.prosecdef OR NOT ('search_path=public' = ANY (p.proconfig)) THEN
      RAISE EXCEPTION '% is not STABLE, SECURITY INVOKER with search_path public', p.signature;
    END IF;
    IF has_function_privilege('anon', p.signature, 'EXECUTE') OR has_function_privilege('authenticated', p.signature, 'EXECUTE')
       OR NOT has_function_privilege('service_role', p.signature, 'EXECUTE') THEN
      RAISE EXCEPTION '% grants changed', p.signature;
    END IF;
  END LOOP;
  IF (SELECT count(*) FROM contract_432.functions_423 c WHERE to_regprocedure(c.signature) IS NOT NULL) <> 2 THEN
    RAISE EXCEPTION 'a function of 423 is missing or its signature changed';
  END IF;
  IF pg_get_function_result('public.backoffice_cs_workspace_facts_v1(text)'::regprocedure) <> 'jsonb' THEN
    RAISE EXCEPTION 'facts no longer return jsonb';
  END IF;
  -- The rollup's columns: names, types and order as 423 has them (an OR REPLACE cannot change them anyway).
  IF pg_get_function_result('public.backoffice_cs_segment_inputs_v1()'::regprocedure) NOT LIKE
     'TABLE(organization_id text, name text, created_at timestamp with time zone, signup_source text, %, trial_started_at timestamp with time zone, trial_ends_at timestamp with time zone, mobile_trial_ends_at timestamp with time zone, %marketing_consent_members integer)' THEN
    RAISE EXCEPTION 'rollup columns: %', pg_get_function_result('public.backoffice_cs_segment_inputs_v1()'::regprocedure);
  END IF;
END $$;

-- Fixtures: one workspace per case, ids t_*. ---------------------------------------------------------------------
INSERT INTO public.organization (id, name, created_at, signup_source, onboarding_status, web_billing_started_at, mobile_billing_started_at) VALUES
  ('t_granted', 'Granted', now() - interval '20 days', NULL, 'launched', NULL, NULL),      -- no web trial, a trial allowance
  ('t_web_running', 'Web Running', now() - interval '20 days', NULL, 'launched', NULL, NULL), -- web trial running and an allowance
  ('t_web_ended', 'Web Ended', now() - interval '40 days', 'web', 'launched', NULL, NULL), -- web trial ended, an allowance
  ('t_ended_only', 'Ended Only', now() - interval '40 days', NULL, 'launched', NULL, NULL), -- web trial ended, no allowance
  ('t_spent', 'Spent', now() - interval '20 days', NULL, 'launched', NULL, NULL),           -- a spent trial allowance only
  ('t_goodwill', 'Goodwill', now() - interval '20 days', NULL, 'launched', NULL, NULL),     -- an active goodwill allowance
  ('t_open_ended', 'Open Ended', now() - interval '20 days', NULL, 'launched', NULL, NULL), -- a trial allowance with no end
  ('t_phone_granted', 'Phone Granted', now() - interval '9 days', 'mobile', 'pending', NULL, NULL),
  ('t_phone_running', 'Phone Running', now() - interval '9 days', 'mobile', 'pending', NULL, NULL),
  ('t_pay_web', 'Pay Web', now() - interval '90 days', NULL, 'launched', now() - interval '30 days', NULL),
  ('t_pay_phone', 'Pay Phone', now() - interval '90 days', 'mobile', 'pending', NULL, now() - interval '30 days'),
  ('t_pay_billed', 'Pay Billed', now() - interval '90 days', NULL, 'launched', NULL, NULL),
  ('t_pay_past_due', 'Pay Past Due', now() - interval '90 days', NULL, 'launched', NULL, NULL),
  ('t_pay_invoice', 'Pay Invoice', now() - interval '90 days', NULL, 'launched', NULL, NULL),
  ('t_not_suspended', 'Suspended', now() - interval '90 days', NULL, 'launched', NULL, NULL),
  ('t_not_old_invoice', 'Old Invoice', now() - interval '200 days', NULL, 'launched', NULL, NULL),
  ('t_not_trial_row', 'Trial Row', now() - interval '5 days', NULL, 'launched', NULL, NULL);

INSERT INTO public.billing_customers (organization_id, card_brand, card_last4, status, billing_started_at, trial_started_at, trial_ends_at) VALUES
  ('t_web_running', NULL, NULL, 'active', NULL, now() - interval '4 days', now() + interval '3 days'),
  ('t_web_ended', NULL, NULL, 'active', NULL, now() - interval '30 days', now() - interval '16 days'),
  ('t_ended_only', NULL, NULL, 'active', NULL, now() - interval '30 days', now() - interval '16 days'),
  ('t_pay_billed', NULL, NULL, 'active', now() - interval '60 days', NULL, NULL),
  ('t_pay_past_due', 'visa', '4242', 'past_due', now() - interval '60 days', NULL, NULL),
  -- Billing started with a card, then suspended: paying under 423, not under 432.
  ('t_not_suspended', 'visa', '4242', 'suspended', now() - interval '60 days', NULL, NULL),
  -- The row the 384 trial start creates: active, billing never started.
  ('t_not_trial_row', NULL, NULL, 'active', NULL, now() - interval '1 day', now() + interval '6 days');

INSERT INTO public.billing_invoices (organization_id, period_start, period_end, total, status, paid_at) VALUES
  ('t_pay_invoice', now() - interval '20 days', now() - interval '13 days', 30, 'paid', now() - interval '12 days'),
  ('t_not_old_invoice', now() - interval '100 days', now() - interval '93 days', 30, 'paid', now() - interval '92 days');

INSERT INTO public.org_seats (organization_id, clerk_user_id, clerk_membership_id, seat_status, mobile_trial_started_at, mobile_trial_ends_at) VALUES
  ('t_phone_granted', 'u_t1', 'm_t1', 'active', now() - interval '9 days', now() - interval '2 days'), -- the phone trial ended
  ('t_phone_running', 'u_t2', 'm_t2', 'active', now() - interval '1 day', now() + interval '2 days');

INSERT INTO public.workspace_allowances (organization_id, kind, amount_usd, expires_at, starts_at, on_end, reason, set_by,
                                         approved_by, approved_at, status, spent_usd, ended_by, ended_at) VALUES
  ('t_granted', 'trial', 40, now() + interval '5 days', now() - interval '2 days', 'pause', 'r', 'agent', 'staff', now() - interval '2 days', 'active', 12.5, NULL, NULL),
  ('t_web_running', 'trial', 40, now() + interval '9 days', now() - interval '1 day', 'pause', 'r', 'agent', 'staff', now() - interval '1 day', 'active', 0, NULL, NULL),
  ('t_web_ended', 'trial', 20, now() + interval '4 days', now() - interval '3 days', 'pause', 'r', 'agent', 'staff', now() - interval '3 days', 'active', 25, NULL, NULL),
  ('t_spent', 'trial', 10, now() + interval '4 days', now() - interval '3 days', 'pause', 'r', 'agent', 'staff', now() - interval '3 days', 'spent', 10, 'job', now() - interval '1 hour'),
  ('t_goodwill', 'goodwill', 50, now() + interval '4 days', now() - interval '3 days', 'pause', 'r', 'agent', 'staff', now() - interval '3 days', 'active', 0, NULL, NULL),
  ('t_open_ended', 'trial', 30, NULL, now() - interval '3 days', 'pause', 'r', 'agent', 'staff', now() - interval '3 days', 'active', 5, NULL, NULL),
  ('t_phone_granted', 'trial', 20, now() + interval '6 days', now() - interval '1 day', 'pause', 'r', 'agent', 'staff', now() - interval '1 day', 'active', 0, NULL, NULL),
  ('t_phone_running', 'trial', 20, now() + interval '6 days', now() - interval '1 day', 'pause', 'r', 'agent', 'staff', now() - interval '1 day', 'active', 0, NULL, NULL);

-- The rollup. ------------------------------------------------------------------------------------------------------
DO $$
DECLARE r record;
BEGIN
  IF (SELECT count(*) FROM public.backoffice_cs_segment_inputs_v1())
     <> (SELECT count(*) FROM public.organization WHERE deleted = false) THEN
    RAISE EXCEPTION 'the rollup is not one row per workspace';
  END IF;
  FOR r IN
    SELECT s.organization_id, s.trial_started_at, s.trial_ends_at, s.mobile_trial_ends_at,
           CASE s.organization_id
             WHEN 't_granted' THEN now() - interval '2 days'
             WHEN 't_web_running' THEN now() - interval '4 days'
             WHEN 't_web_ended' THEN now() - interval '3 days'
             WHEN 't_ended_only' THEN now() - interval '30 days'
             WHEN 't_open_ended' THEN now() - interval '3 days'
             WHEN 't_phone_granted' THEN now() - interval '1 day'
             WHEN 't_phone_running' THEN now() - interval '1 day'
             WHEN 't_not_trial_row' THEN now() - interval '1 day'
           END AS want_started,
           CASE s.organization_id
             WHEN 't_granted' THEN now() + interval '5 days'      -- the allowance
             WHEN 't_web_running' THEN now() + interval '3 days'  -- the running web trial wins
             WHEN 't_web_ended' THEN now() + interval '4 days'    -- the allowance after an ended web trial
             WHEN 't_ended_only' THEN now() - interval '16 days'  -- the ended web trial as recorded
             WHEN 't_phone_granted' THEN now() + interval '6 days'
             WHEN 't_phone_running' THEN now() + interval '6 days'
             WHEN 't_not_trial_row' THEN now() + interval '6 days'
           END AS want_ends,
           CASE s.organization_id
             WHEN 't_phone_granted' THEN now() + interval '6 days' -- phone trial ended: the allowance
             WHEN 't_phone_running' THEN now() + interval '2 days' -- the running phone trial wins
           END AS want_mobile
    FROM public.backoffice_cs_segment_inputs_v1() s
    WHERE s.organization_id LIKE 't\_%'
  LOOP
    IF r.trial_started_at IS DISTINCT FROM r.want_started OR r.trial_ends_at IS DISTINCT FROM r.want_ends
       OR r.mobile_trial_ends_at IS DISTINCT FROM r.want_mobile THEN
      RAISE EXCEPTION 'rollup trial of %: started %, ends %, phone %; expected %, %, %', r.organization_id,
        r.trial_started_at, r.trial_ends_at, r.mobile_trial_ends_at, r.want_started, r.want_ends, r.want_mobile;
    END IF;
  END LOOP;
END $$;

-- The facts. -------------------------------------------------------------------------------------------------------
DO $$
DECLARE
  f jsonb;
  c record;
BEGIN
  -- The billing keys: 423's and trial_source. The other sections are 423's (423's contract checks them).
  f := public.backoffice_cs_workspace_facts_v1('t_granted');
  IF pg_temp.cs_keys(f->'billing') <> pg_temp.cs_sorted(ARRAY['status', 'card_on_file', 'billing_started_at', 'paying', 'trial_active',
       'trial_ends_at', 'trial_source', 'trial_credit_usd', 'trial_credit_remaining_usd', 'credit_remaining_usd', 'monthly_spend_limit_usd',
       'usage_7d_usd', 'usage_prev_7d_usd', 'usage_28d_usd', 'last_invoice_at', 'open_invoice_usd', 'seat_discount_percent']) THEN
    RAISE EXCEPTION 'billing keys: %', pg_temp.cs_keys(f->'billing');
  END IF;
  IF pg_temp.cs_keys(f) <> pg_temp.cs_sorted(ARRAY['generated_at', 'organization', 'segment', 'health_score', 'members', 'seats',
       'research', 'plays', 'outcomes', 'activity', 'billing', 'requests', 'mailboxes', 'notes', 'support', 'caps', 'recommendations']) THEN
    RAISE EXCEPTION 'facts top-level keys: %', pg_temp.cs_keys(f);
  END IF;
  -- The allowance's money is the trial credit when the allowance is the trial.
  IF (f->'billing'->>'trial_credit_usd')::numeric <> 40 OR (f->'billing'->>'trial_credit_remaining_usd')::numeric <> 27.5 THEN
    RAISE EXCEPTION 't_granted trial credit: %', f->'billing';
  END IF;
  f := public.backoffice_cs_workspace_facts_v1('t_web_ended');
  IF (f->'billing'->>'trial_credit_remaining_usd')::numeric <> 0 THEN
    RAISE EXCEPTION 'an overspent allowance leaves 0, not %', f->'billing'->>'trial_credit_remaining_usd';
  END IF;
  f := public.backoffice_cs_workspace_facts_v1('t_web_running');
  IF f->'billing'->'trial_credit_usd' <> 'null'::jsonb THEN
    RAISE EXCEPTION 'a running web trial without credit rows has no trial credit: %', f->'billing';
  END IF;

  FOR c IN
    SELECT * FROM (VALUES
      ('t_granted', true, now() + interval '5 days', 'workspace_allowances', false),
      ('t_web_running', true, now() + interval '3 days', 'billing_customers', false),
      ('t_web_ended', true, now() + interval '4 days', 'workspace_allowances', false),
      ('t_ended_only', false, now() - interval '16 days', 'billing_customers', false),
      ('t_spent', false, NULL, NULL, false),
      ('t_goodwill', false, NULL, NULL, false),
      ('t_open_ended', true, NULL, 'workspace_allowances', false),
      ('t_phone_granted', true, now() + interval '6 days', 'workspace_allowances', false),
      ('t_phone_running', true, now() + interval '2 days', 'org_seats', false),
      ('t_pay_web', false, NULL, NULL, true),
      ('t_pay_phone', false, NULL, NULL, true),
      ('t_pay_billed', false, NULL, NULL, true),
      ('t_pay_past_due', false, NULL, NULL, true),
      ('t_pay_invoice', false, NULL, NULL, true),
      ('t_not_suspended', false, NULL, NULL, false),
      ('t_not_old_invoice', false, NULL, NULL, false),
      ('t_not_trial_row', true, now() + interval '6 days', 'billing_customers', false)
    ) AS v(org, active, ends_at, source, paying)
  LOOP
    f := public.backoffice_cs_workspace_facts_v1(c.org);
    IF (f->'billing'->>'trial_active')::boolean IS DISTINCT FROM c.active
       OR (f->'billing'->>'trial_ends_at')::timestamptz IS DISTINCT FROM c.ends_at
       OR f->'billing'->>'trial_source' IS DISTINCT FROM c.source
       OR (f->'billing'->>'paying')::boolean IS DISTINCT FROM c.paying THEN
      RAISE EXCEPTION 'facts of %: active %, ends %, source %, paying %; expected %, %, %, %', c.org,
        f->'billing'->>'trial_active', f->'billing'->>'trial_ends_at', f->'billing'->>'trial_source', f->'billing'->>'paying',
        c.active, c.ends_at, c.source, c.paying;
    END IF;
  END LOOP;

  IF public.backoffice_cs_workspace_facts_v1('t_nobody') IS NOT NULL THEN
    RAISE EXCEPTION 'an unknown workspace has facts';
  END IF;
END $$;

-- Read-only: nothing above wrote a row (the functions are STABLE; a write would have failed). Clean up the fixtures.
DELETE FROM public.workspace_allowances WHERE organization_id LIKE 't\_%';
DELETE FROM public.org_seats WHERE organization_id LIKE 't\_%';
DELETE FROM public.billing_invoices WHERE organization_id LIKE 't\_%';
DELETE FROM public.billing_customers WHERE organization_id LIKE 't\_%';
DELETE FROM public.organization WHERE id LIKE 't\_%';
