-- Migration 434's contract. Run by tests/run-backoffice-cs-agent-plan-facts-contract.sh on a disposable database, in
-- one transaction (now() is the same instant in the fixtures and in the functions). Its fixtures are removed at the
-- end, so 432's own contract can run on the same database after the rollback.

CREATE FUNCTION pg_temp.cs_keys(j jsonb) RETURNS text[] LANGUAGE sql AS $$
  SELECT coalesce(array_agg(k ORDER BY k), '{}'::text[]) FROM jsonb_object_keys(j) k
$$;
CREATE FUNCTION pg_temp.cs_sorted(a text[]) RETURNS text[] LANGUAGE sql AS $$
  SELECT array_agg(x ORDER BY x) FROM unnest(a) x
$$;
-- Every check that passes adds a row; the last statement reports the count.
CREATE TEMP TABLE contract_434_passed (n serial, what text NOT NULL);

-- 432's facts function, as the runner kept it, under another name: the reference for "every other key unchanged".
DO $$
DECLARE d text;
BEGIN
  SELECT c.definition INTO d FROM contract_434.functions_432 c WHERE c.signature = 'public.backoffice_cs_workspace_facts_v1(text)';
  IF d IS NULL OR position('CREATE OR REPLACE FUNCTION public.backoffice_cs_workspace_facts_v1(p_org text)' IN d) <> 1 THEN
    RAISE EXCEPTION 'the runner did not keep 432''s facts definition';
  END IF;
  EXECUTE replace(d, 'CREATE OR REPLACE FUNCTION public.backoffice_cs_workspace_facts_v1(p_org text)',
                     'CREATE FUNCTION pg_temp.facts_432(p_org text)');
END $$;

-- The shape: 432's signature, result, volatility, security and grants; the rollup untouched. -------------------
DO $$
DECLARE p record;
BEGIN
  SELECT f.provolatile, f.prosecdef, f.proconfig INTO p
  FROM pg_proc f WHERE f.oid = to_regprocedure('public.backoffice_cs_workspace_facts_v1(text)');
  IF NOT FOUND THEN
    RAISE EXCEPTION 'the facts function is missing or its signature changed';
  END IF;
  IF p.provolatile <> 's' OR p.prosecdef OR NOT ('search_path=public' = ANY (p.proconfig)) THEN
    RAISE EXCEPTION 'the facts function is not STABLE, SECURITY INVOKER with search_path public';
  END IF;
  IF pg_get_function_result('public.backoffice_cs_workspace_facts_v1(text)'::regprocedure) <> 'jsonb' THEN
    RAISE EXCEPTION 'facts no longer return jsonb';
  END IF;
  IF has_function_privilege('anon', 'public.backoffice_cs_workspace_facts_v1(text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.backoffice_cs_workspace_facts_v1(text)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.backoffice_cs_workspace_facts_v1(text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'facts grants changed';
  END IF;
  IF (SELECT proacl::text FROM pg_proc WHERE oid = 'public.backoffice_cs_workspace_facts_v1(text)'::regprocedure)
     IS DISTINCT FROM (SELECT c.acl FROM contract_434.functions_432 c WHERE c.signature = 'public.backoffice_cs_workspace_facts_v1(text)') THEN
    RAISE EXCEPTION 'facts grants differ from 432''s';
  END IF;
  INSERT INTO contract_434_passed (what) VALUES ('facts signature, result, volatility, security, grants');

  IF pg_get_functiondef('public.backoffice_cs_segment_inputs_v1()'::regprocedure)
       IS DISTINCT FROM (SELECT c.definition FROM contract_434.functions_432 c WHERE c.signature = 'public.backoffice_cs_segment_inputs_v1()')
     OR obj_description('public.backoffice_cs_segment_inputs_v1()'::regprocedure, 'pg_proc')
       IS DISTINCT FROM (SELECT c.comment FROM contract_434.functions_432 c WHERE c.signature = 'public.backoffice_cs_segment_inputs_v1()')
     OR (SELECT proacl::text FROM pg_proc WHERE oid = 'public.backoffice_cs_segment_inputs_v1()'::regprocedure)
       IS DISTINCT FROM (SELECT c.acl FROM contract_434.functions_432 c WHERE c.signature = 'public.backoffice_cs_segment_inputs_v1()') THEN
    RAISE EXCEPTION '434 changed backoffice_cs_segment_inputs_v1()';
  END IF;
  INSERT INTO contract_434_passed (what) VALUES ('the rollup is 432''s, untouched');
END $$;

-- Fixtures: one workspace per case, ids p4_*. "today" is now()'s UTC date, as the function reads it. -------------
INSERT INTO public.organization (id, name, created_at, signup_source, onboarding_status) VALUES
  ('p4_none', 'No Plan', now() - interval '40 days', NULL, 'launched'),            -- no workspace_plans row
  ('p4_pilot', 'Pilot', now() - interval '40 days', NULL, 'launched'),             -- an active pilot
  ('p4_deploy', 'Deployment', now() - interval '400 days', NULL, 'launched'),      -- an active deployment, an ended pilot
  ('p4_converted', 'Converted', now() - interval '200 days', NULL, 'launched'),    -- a pilot converted to a deployment
  ('p4_ended', 'Ended', now() - interval '200 days', NULL, 'launched'),            -- only an ended pilot
  ('p4_proposed', 'Proposed', now() - interval '20 days', NULL, 'launched'),       -- a proposed pilot, a cancelled deployment
  ('p4_self_serve', 'Self Serve', now() - interval '20 days', NULL, 'launched'),   -- an active self_serve plan
  ('p4_open_term', 'Open Term', now() - interval '90 days', NULL, 'launched'),     -- a deployment with no term and no fee
  ('p4_future', 'Future', now() - interval '10 days', 'mobile', 'pending'),        -- a pilot that starts in 3 days
  ('p4_past', 'Past', now() - interval '120 days', NULL, 'launched');              -- a deployment still active after its term

-- Other sections with data, so "every other key unchanged" compares more than empty aggregates.
INSERT INTO public.billing_customers (organization_id, card_brand, card_last4, status, billing_started_at, trial_started_at, trial_ends_at) VALUES
  ('p4_pilot', NULL, NULL, 'active', NULL, now() - interval '5 days', now() + interval '2 days'),
  ('p4_deploy', 'visa', '4242', 'active', now() - interval '300 days', NULL, NULL);
INSERT INTO public.workspace_allowances (organization_id, kind, amount_usd, expires_at, starts_at, on_end, reason, set_by,
                                         approved_by, approved_at, status, spent_usd) VALUES
  ('p4_none', 'trial', 40, now() + interval '5 days', now() - interval '2 days', 'pause', 'r', 'agent', 'staff', now() - interval '2 days', 'active', 12.5);
INSERT INTO public.billing_invoices (organization_id, period_start, period_end, total, status, paid_at) VALUES
  ('p4_deploy', now() - interval '20 days', now() - interval '13 days', 900, 'paid', now() - interval '12 days');
INSERT INTO public.campaigns (organization_id, user_id, name, status, created_at, launched_at) VALUES
  ('p4_pilot', 'u_p4', 'Play one', 'active', now() - interval '20 days', now() - interval '19 days'),
  ('p4_deploy', 'u_p4', 'Play two', 'draft', now() - interval '3 days', NULL);
INSERT INTO public.backoffice_org_notes (organization_id, body, created_by) VALUES
  ('p4_deploy', 'a note', 'agent');

DO $$
DECLARE
  today date := (now() AT TIME ZONE 'UTC')::date;
  dep uuid;
BEGIN
  INSERT INTO public.workspace_plans (organization_id, plan, fee_usd, included_usage_usd, term_start, term_end, seats_included,
                                      success_criteria, owner, status, created_by, approved_by, approved_at, created_at) VALUES
    ('p4_pilot', 'pilot', 1500, NULL, today - 30, today + 30, 3, '{"meetings": 6}', 'staff', 'active', 'agent', 'staff', now() - interval '30 days', now() - interval '30 days'),
    ('p4_deploy', 'pilot', 1000, NULL, today - 400, today - 340, 3, '{"meetings": 4}', 'staff', 'ended', 'agent', 'staff', now() - interval '400 days', now() - interval '400 days'),
    ('p4_deploy', 'deployment', 12000, 1000, today - 280, today + 85, 5, '{"meetings": 20, "replies": 50}', 'staff', 'active', 'agent', 'staff', now() - interval '280 days', now() - interval '280 days'),
    ('p4_ended', 'pilot', 1500, NULL, today - 100, today - 40, 3, '{"meetings": 6}', 'staff', 'ended', 'agent', 'staff', now() - interval '100 days', now() - interval '100 days'),
    ('p4_proposed', 'pilot', 1500, NULL, today, today + 60, 3, '{"meetings": 6}', NULL, 'proposed', 'agent', NULL, NULL, now() - interval '1 day'),
    ('p4_proposed', 'deployment', 9000, NULL, today - 10, today + 355, 5, '{}', NULL, 'cancelled', 'agent', NULL, NULL, now() - interval '10 days'),
    ('p4_self_serve', 'self_serve', NULL, NULL, today - 10, NULL, NULL, '{}', NULL, 'active', 'agent', 'staff', now() - interval '10 days', now() - interval '10 days'),
    ('p4_open_term', 'deployment', NULL, NULL, NULL, NULL, NULL, '["10 meetings booked", "a champion named"]', 'staff', 'active', 'agent', 'staff', now() - interval '60 days', now() - interval '60 days'),
    ('p4_future', 'pilot', 0, 250.5, today + 3, today + 33, NULL, '{"meetings": 4, "replies": 2.5, "note": "x", "nested": {"a": 1}, "flag": true}', 'staff', 'active', 'agent', 'staff', now(), now()),
    ('p4_past', 'deployment', 6000, 500, today - 100, today - 10, 2, '{"meetings": 8}', 'staff', 'active', 'agent', 'staff', now() - interval '100 days', now() - interval '100 days');

  INSERT INTO public.workspace_plans (organization_id, plan, fee_usd, included_usage_usd, term_start, term_end, seats_included,
                                      success_criteria, owner, status, created_by, approved_by, approved_at, created_at)
  VALUES ('p4_converted', 'deployment', 24000, 2000, today - 50, today + 315, 10, '{"meetings": 40}', 'staff', 'active', 'agent', 'staff', now() - interval '50 days', now() - interval '50 days')
  RETURNING id INTO dep;
  INSERT INTO public.workspace_plans (organization_id, plan, fee_usd, included_usage_usd, term_start, term_end, seats_included,
                                      success_criteria, owner, status, converted_to, created_by, approved_by, approved_at, created_at)
  VALUES ('p4_converted', 'pilot', 1500, NULL, today - 110, today - 50, 3, '{"meetings": 6}', 'staff', 'converted', dep, 'agent', 'staff', now() - interval '110 days', now() - interval '110 days');
END $$;

-- Every other key unchanged: 434's facts without `plan` are 432's facts, for every workspace. ------------------
DO $$
DECLARE
  o record;
  f jsonb;
  old jsonb;
BEGIN
  FOR o IN SELECT id FROM public.organization ORDER BY id LOOP
    f := public.backoffice_cs_workspace_facts_v1(o.id);
    old := pg_temp.facts_432(o.id);
    IF NOT (f ? 'plan') THEN
      RAISE EXCEPTION 'facts of % have no plan key', o.id;
    END IF;
    IF pg_temp.cs_keys(f) <> pg_temp.cs_sorted(pg_temp.cs_keys(old) || 'plan'::text) THEN
      RAISE EXCEPTION 'facts keys of %: %; 432 has %', o.id, pg_temp.cs_keys(f), pg_temp.cs_keys(old);
    END IF;
    IF (f - 'plan') IS DISTINCT FROM old THEN
      RAISE EXCEPTION 'facts of % differ from 432''s beyond plan: % vs %', o.id, f - 'plan', old;
    END IF;
    INSERT INTO contract_434_passed (what) VALUES ('432''s keys unchanged for ' || o.id);
  END LOOP;
  IF (SELECT count(*) FROM public.organization WHERE id LIKE 'p4\_%') <> 10 THEN
    RAISE EXCEPTION 'fixtures missing';
  END IF;
  -- The top-level keys, spelled out: 432's seventeen and plan.
  IF pg_temp.cs_keys(public.backoffice_cs_workspace_facts_v1('p4_pilot')) <> pg_temp.cs_sorted(ARRAY['generated_at', 'organization',
       'segment', 'health_score', 'members', 'seats', 'research', 'plays', 'outcomes', 'activity', 'billing', 'requests', 'mailboxes',
       'notes', 'support', 'caps', 'recommendations', 'plan']) THEN
    RAISE EXCEPTION 'facts top-level keys: %', pg_temp.cs_keys(public.backoffice_cs_workspace_facts_v1('p4_pilot'));
  END IF;
  INSERT INTO contract_434_passed (what) VALUES ('top-level keys are 432''s and plan');
  IF public.backoffice_cs_workspace_facts_v1('p4_nobody') IS NOT NULL THEN
    RAISE EXCEPTION 'an unknown workspace has facts';
  END IF;
  INSERT INTO contract_434_passed (what) VALUES ('unknown workspace: NULL');
END $$;

-- plan, case by case. ------------------------------------------------------------------------------------------
DO $$
DECLARE
  today date := (now() AT TIME ZONE 'UTC')::date;
  c record;
  got jsonb;
BEGIN
  FOR c IN
    SELECT * FROM (VALUES
      ('p4_none', NULL::jsonb),
      ('p4_pilot', jsonb_build_object('kind', 'pilot', 'status', 'active', 'term_start', today - 30, 'term_end', today + 30,
         'term_days', 60, 'days_elapsed', 30, 'fee_usd', 1500, 'included_usage_usd', NULL, 'seats_included', 3,
         'success_criteria', '{"meetings": 6}'::jsonb)),
      ('p4_deploy', jsonb_build_object('kind', 'deployment', 'status', 'active', 'term_start', today - 280, 'term_end', today + 85,
         'term_days', 365, 'days_elapsed', 280, 'fee_usd', 12000, 'included_usage_usd', 1000, 'seats_included', 5,
         'success_criteria', '{"meetings": 20, "replies": 50}'::jsonb)),
      ('p4_converted', jsonb_build_object('kind', 'deployment', 'status', 'active', 'term_start', today - 50, 'term_end', today + 315,
         'term_days', 365, 'days_elapsed', 50, 'fee_usd', 24000, 'included_usage_usd', 2000, 'seats_included', 10,
         'success_criteria', '{"meetings": 40}'::jsonb)),
      ('p4_ended', NULL::jsonb),
      ('p4_proposed', NULL::jsonb),
      ('p4_self_serve', NULL::jsonb),
      ('p4_open_term', jsonb_build_object('kind', 'deployment', 'status', 'active', 'term_start', NULL, 'term_end', NULL,
         'term_days', NULL, 'days_elapsed', NULL, 'fee_usd', NULL, 'included_usage_usd', NULL, 'seats_included', NULL,
         'success_criteria', '{}'::jsonb)),
      ('p4_future', jsonb_build_object('kind', 'pilot', 'status', 'active', 'term_start', today + 3, 'term_end', today + 33,
         'term_days', 30, 'days_elapsed', 0, 'fee_usd', 0, 'included_usage_usd', 250.5, 'seats_included', NULL,
         'success_criteria', '{"meetings": 4, "replies": 2.5}'::jsonb)),
      ('p4_past', jsonb_build_object('kind', 'deployment', 'status', 'active', 'term_start', today - 100, 'term_end', today - 10,
         'term_days', 90, 'days_elapsed', 100, 'fee_usd', 6000, 'included_usage_usd', 500, 'seats_included', 2,
         'success_criteria', '{"meetings": 8}'::jsonb))
    ) AS v(org, want)
  LOOP
    got := public.backoffice_cs_workspace_facts_v1(c.org)->'plan';
    IF c.want IS NULL THEN
      IF got IS DISTINCT FROM 'null'::jsonb THEN
        RAISE EXCEPTION 'plan of %: %; expected null', c.org, got;
      END IF;
    ELSIF got IS DISTINCT FROM c.want OR pg_temp.cs_keys(got) <> pg_temp.cs_keys(c.want) THEN
      RAISE EXCEPTION 'plan of %: %; expected %', c.org, got, c.want;
    END IF;
    INSERT INTO contract_434_passed (what) VALUES ('plan of ' || c.org);
  END LOOP;

  -- The JSON types the backoffice reads: dates as YYYY-MM-DD strings, the day counts as integers.
  got := public.backoffice_cs_workspace_facts_v1('p4_pilot')->'plan';
  IF jsonb_typeof(got->'term_start') <> 'string' OR got->>'term_start' !~ '^\d{4}-\d{2}-\d{2}$'
     OR jsonb_typeof(got->'term_end') <> 'string' OR got->>'term_end' !~ '^\d{4}-\d{2}-\d{2}$'
     OR jsonb_typeof(got->'term_days') <> 'number' OR got->>'term_days' !~ '^\d+$'
     OR jsonb_typeof(got->'days_elapsed') <> 'number' OR got->>'days_elapsed' !~ '^\d+$'
     OR jsonb_typeof(got->'success_criteria') <> 'object' OR got->>'status' <> 'active' THEN
    RAISE EXCEPTION 'plan JSON types: %', got;
  END IF;
  INSERT INTO contract_434_passed (what) VALUES ('plan JSON types');
END $$;

-- Read-only: nothing above wrote a row (the function is STABLE; a write would have failed). Clean up the fixtures.
DELETE FROM public.workspace_plans WHERE organization_id LIKE 'p4\_%' AND converted_to IS NOT NULL;
DELETE FROM public.workspace_plans WHERE organization_id LIKE 'p4\_%';
DELETE FROM public.workspace_allowances WHERE organization_id LIKE 'p4\_%';
DELETE FROM public.backoffice_org_notes WHERE organization_id LIKE 'p4\_%';
DELETE FROM public.campaigns WHERE organization_id LIKE 'p4\_%';
DELETE FROM public.billing_invoices WHERE organization_id LIKE 'p4\_%';
DELETE FROM public.billing_customers WHERE organization_id LIKE 'p4\_%';
DELETE FROM public.organization WHERE id LIKE 'p4\_%';

SELECT format('backoffice cs agent plan facts contract: %s checks passed', count(*)) AS result FROM contract_434_passed;
