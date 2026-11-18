-- Migration 430's contract. Run by tests/run-backoffice-cs-agent-economics-contract.sh on a disposable database.

-- refuses(sql, sqlstate, what): the statement must fail with exactly that error (23514 check, 23505 unique,
-- 23503 foreign key, 23502 not null, 428C9 a generated column written).
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

-- Access: the service role only, RLS on, no policies; usage and billing_settings untouched by 430 (applied twice).
DO $$
BEGIN
  IF has_table_privilege('anon', 'public.workspace_economics', 'SELECT')
     OR has_table_privilege('authenticated', 'public.workspace_economics', 'SELECT')
     OR has_table_privilege('anon', 'public.workspace_economics', 'INSERT')
     OR has_table_privilege('authenticated', 'public.workspace_economics', 'INSERT')
     OR has_table_privilege('anon', 'public.workspace_economics', 'UPDATE')
     OR has_table_privilege('authenticated', 'public.workspace_economics', 'UPDATE')
     OR has_table_privilege('anon', 'public.workspace_economics', 'DELETE')
     OR has_table_privilege('authenticated', 'public.workspace_economics', 'DELETE') THEN
    RAISE EXCEPTION 'anon/authenticated still have privileges on workspace_economics';
  END IF;
  IF NOT has_table_privilege('service_role', 'public.workspace_economics', 'INSERT')
     OR NOT has_table_privilege('service_role', 'public.workspace_economics', 'UPDATE') THEN
    RAISE EXCEPTION 'service_role cannot write workspace_economics';
  END IF;
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.workspace_economics'::regclass) THEN
    RAISE EXCEPTION 'RLS is off on workspace_economics';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'workspace_economics') THEN
    RAISE EXCEPTION 'workspace_economics has a policy';
  END IF;
  IF EXISTS (SELECT * FROM public.usage EXCEPT SELECT * FROM contract_fixture.usage_before)
     OR EXISTS (SELECT * FROM contract_fixture.usage_before EXCEPT SELECT * FROM public.usage) THEN
    RAISE EXCEPTION '430 changed usage';
  END IF;
  IF EXISTS (SELECT * FROM public.billing_settings EXCEPT SELECT * FROM contract_fixture.billing_settings_before)
     OR EXISTS (SELECT * FROM contract_fixture.billing_settings_before EXCEPT SELECT * FROM public.billing_settings) THEN
    RAISE EXCEPTION '430 changed billing_settings';
  END IF;
END $$;

-- The columns, as the backoffice writes them.
DO $$
DECLARE
  expected text[] := ARRAY['id', 'organization_id', 'user_id', 'user_key', 'cycle_start', 'cycle_end',
    'seat_revenue_usd', 'workspace_revenue_usd', 'usage_revenue_usd', 'usage_original_cost_usd', 'provider_cost_usd',
    'allocated_infra_usd', 'contribution_usd', 'margin_percent', 'inputs', 'computed_at'];
  got text[];
BEGIN
  SELECT array_agg(column_name::text ORDER BY ordinal_position) INTO got
  FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'workspace_economics';
  IF got IS DISTINCT FROM expected THEN RAISE EXCEPTION 'workspace_economics columns are %', got; END IF;
  IF (SELECT is_generated FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'workspace_economics' AND column_name = 'user_key') <> 'ALWAYS' THEN
    RAISE EXCEPTION 'user_key is not generated';
  END IF;
END $$;

-- A browser key is refused.
SET ROLE anon;
DO $$ BEGIN
  BEGIN
    PERFORM count(*) FROM public.workspace_economics;
    RAISE EXCEPTION 'anon read workspace_economics';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SET ROLE authenticated;
DO $$ BEGIN
  BEGIN
    PERFORM count(*) FROM public.workspace_economics;
    RAISE EXCEPTION 'authenticated read workspace_economics';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    INSERT INTO public.workspace_economics (organization_id, cycle_start, cycle_end) VALUES ('org_a', '2026-11-02', '2026-11-30');
    RAISE EXCEPTION 'authenticated wrote workspace_economics';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;

-- The service role writes, as the backoffice does.
SET ROLE service_role;

-- A workspace row and two person rows for one cycle: contribution is the arithmetic, margin is NULL without revenue.
INSERT INTO public.workspace_economics
  (organization_id, user_id, cycle_start, cycle_end, seat_revenue_usd, workspace_revenue_usd, usage_revenue_usd,
   usage_original_cost_usd, provider_cost_usd, allocated_infra_usd, contribution_usd, margin_percent, inputs)
VALUES
  ('org_a', NULL, '2026-11-02', '2026-11-30', 12.00, 0, 3.00, 1.00, 13.80, 0, 0.20, 1.33, '{"seats": 1}'),
  ('org_a', 'user_1', '2026-11-02', '2026-11-30', 12.00, 0, 3.00, 1.00, 13.80, 0, 0.20, 1.33, '{}'),
  ('org_a', 'user_2', '2026-11-02', '2026-11-30', 0, 0, 0, 0, 6.90, 0, -6.90, NULL, '{}'),
  ('org_b', NULL, '2026-11-02', '2026-11-30', 0, 0, 0, 0, 0, 0, 0, NULL, '{}');

DO $$
DECLARE r public.workspace_economics%ROWTYPE;
BEGIN
  SELECT * INTO r FROM public.workspace_economics WHERE organization_id = 'org_a' AND user_id IS NULL;
  IF r.user_key <> '' OR r.computed_at IS NULL OR r.id IS NULL THEN RAISE EXCEPTION 'defaults not applied: %', r; END IF;
  SELECT * INTO r FROM public.workspace_economics WHERE organization_id = 'org_a' AND user_id = 'user_1';
  IF r.user_key <> 'user_1' THEN RAISE EXCEPTION 'user_key is not the person: %', r.user_key; END IF;
END $$;

-- One row per organization, person and cycle: a second workspace row is refused (NULL user_id does not escape the key).
SELECT pg_temp.refuses($$INSERT INTO public.workspace_economics (organization_id, user_id, cycle_start, cycle_end)
  VALUES ('org_a', NULL, '2026-11-02', '2026-11-30')$$, '23505', 'a second workspace row for the cycle');
SELECT pg_temp.refuses($$INSERT INTO public.workspace_economics (organization_id, user_id, cycle_start, cycle_end)
  VALUES ('org_a', 'user_1', '2026-11-02', '2026-11-30')$$, '23505', 'a second person row for the cycle');
-- The next cycle is its own row.
INSERT INTO public.workspace_economics (organization_id, user_id, cycle_start, cycle_end)
  VALUES ('org_a', NULL, '2026-11-30', '2026-12-28');

-- The upsert the backoffice sends (PostgREST on_conflict=organization_id,user_key,cycle_start, merge duplicates):
-- running a cycle twice replaces its row and leaves one.
INSERT INTO public.workspace_economics AS t
  (organization_id, user_id, cycle_start, cycle_end, seat_revenue_usd, provider_cost_usd, contribution_usd,
   margin_percent, inputs, computed_at)
VALUES ('org_a', NULL, '2026-11-02', '2026-11-30', 12.00, 15.00, -3.00, -25.00, '{"run": 2}', now())
ON CONFLICT (organization_id, user_key, cycle_start) DO UPDATE SET
  seat_revenue_usd = EXCLUDED.seat_revenue_usd, workspace_revenue_usd = EXCLUDED.workspace_revenue_usd,
  usage_revenue_usd = EXCLUDED.usage_revenue_usd, usage_original_cost_usd = EXCLUDED.usage_original_cost_usd,
  provider_cost_usd = EXCLUDED.provider_cost_usd, allocated_infra_usd = EXCLUDED.allocated_infra_usd,
  contribution_usd = EXCLUDED.contribution_usd, margin_percent = EXCLUDED.margin_percent,
  inputs = EXCLUDED.inputs, computed_at = EXCLUDED.computed_at;
DO $$ BEGIN
  IF (SELECT count(*) FROM public.workspace_economics
      WHERE organization_id = 'org_a' AND user_id IS NULL AND cycle_start = '2026-11-02') <> 1 THEN
    RAISE EXCEPTION 'the upsert added a row';
  END IF;
  IF (SELECT contribution_usd FROM public.workspace_economics
      WHERE organization_id = 'org_a' AND user_id IS NULL AND cycle_start = '2026-11-02') <> -3.00 THEN
    RAISE EXCEPTION 'the upsert did not replace the row';
  END IF;
END $$;

-- user_key is never written.
SELECT pg_temp.refuses($$INSERT INTO public.workspace_economics (organization_id, user_key, cycle_start, cycle_end)
  VALUES ('org_c', 'x', '2026-11-02', '2026-11-30')$$, '428C9', 'user_key written');

-- The arithmetic is checked: the contribution must be the revenue minus the costs.
SELECT pg_temp.refuses($$INSERT INTO public.workspace_economics
  (organization_id, cycle_start, cycle_end, seat_revenue_usd, provider_cost_usd, contribution_usd)
  VALUES ('org_c', '2026-11-02', '2026-11-30', 12.00, 15.00, 0)$$, '23514', 'a contribution that is not the arithmetic');
SELECT pg_temp.refuses($$INSERT INTO public.workspace_economics
  (organization_id, cycle_start, cycle_end, provider_cost_usd, contribution_usd, margin_percent)
  VALUES ('org_c', '2026-11-02', '2026-11-30', 15.00, -15.00, -100.00)$$, '23514', 'a margin without revenue');

-- Never negative revenue or cost; a cycle ends after it starts; inputs is an object.
SELECT pg_temp.refuses($$INSERT INTO public.workspace_economics (organization_id, cycle_start, cycle_end, seat_revenue_usd, contribution_usd)
  VALUES ('org_c', '2026-11-02', '2026-11-30', -1, -1)$$, '23514', 'negative seat revenue');
SELECT pg_temp.refuses($$INSERT INTO public.workspace_economics (organization_id, cycle_start, cycle_end, workspace_revenue_usd, contribution_usd)
  VALUES ('org_c', '2026-11-02', '2026-11-30', -1, -1)$$, '23514', 'negative workspace revenue');
SELECT pg_temp.refuses($$INSERT INTO public.workspace_economics (organization_id, cycle_start, cycle_end, usage_revenue_usd, contribution_usd)
  VALUES ('org_c', '2026-11-02', '2026-11-30', -1, -1)$$, '23514', 'negative usage revenue');
SELECT pg_temp.refuses($$INSERT INTO public.workspace_economics (organization_id, cycle_start, cycle_end, usage_original_cost_usd, contribution_usd)
  VALUES ('org_c', '2026-11-02', '2026-11-30', -1, 1)$$, '23514', 'negative usage cost');
SELECT pg_temp.refuses($$INSERT INTO public.workspace_economics (organization_id, cycle_start, cycle_end, provider_cost_usd, contribution_usd)
  VALUES ('org_c', '2026-11-02', '2026-11-30', -1, 1)$$, '23514', 'negative provider cost');
SELECT pg_temp.refuses($$INSERT INTO public.workspace_economics (organization_id, cycle_start, cycle_end, allocated_infra_usd, contribution_usd)
  VALUES ('org_c', '2026-11-02', '2026-11-30', -1, 1)$$, '23514', 'negative infrastructure');
SELECT pg_temp.refuses($$INSERT INTO public.workspace_economics (organization_id, cycle_start, cycle_end)
  VALUES ('org_c', '2026-11-30', '2026-11-30')$$, '23514', 'a cycle that ends when it starts');
SELECT pg_temp.refuses($$INSERT INTO public.workspace_economics (organization_id, cycle_start, cycle_end, inputs)
  VALUES ('org_c', '2026-11-02', '2026-11-30', '[]')$$, '23514', 'inputs that is not an object');
SELECT pg_temp.refuses($$INSERT INTO public.workspace_economics (organization_id, user_id, cycle_start, cycle_end)
  VALUES ('org_c', '', '2026-11-02', '2026-11-30')$$, '23514', 'an empty user_id');
SELECT pg_temp.refuses($$INSERT INTO public.workspace_economics (organization_id, cycle_start, cycle_end)
  VALUES ('org_missing', '2026-11-02', '2026-11-30')$$, '23503', 'an unknown organization');
SELECT pg_temp.refuses($$INSERT INTO public.workspace_economics (organization_id, cycle_end)
  VALUES ('org_c', '2026-11-30')$$, '23502', 'no cycle_start');

RESET ROLE;

-- Deleting an organization deletes its snapshots; the others stay.
DELETE FROM public.organization WHERE id = 'org_b';
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM public.workspace_economics WHERE organization_id = 'org_b') THEN
    RAISE EXCEPTION 'org_b snapshots outlived the organization';
  END IF;
  IF (SELECT count(*) FROM public.workspace_economics WHERE organization_id = 'org_a') <> 4 THEN
    RAISE EXCEPTION 'org_a snapshots changed';
  END IF;
END $$;

-- The writes above touched neither usage nor billing_settings.
DO $$ BEGIN
  IF EXISTS (SELECT * FROM public.usage EXCEPT SELECT * FROM contract_fixture.usage_before)
     OR EXISTS (SELECT * FROM contract_fixture.usage_before EXCEPT SELECT * FROM public.usage) THEN
    RAISE EXCEPTION 'usage changed';
  END IF;
  IF EXISTS (SELECT * FROM public.billing_settings EXCEPT SELECT * FROM contract_fixture.billing_settings_before)
     OR EXISTS (SELECT * FROM contract_fixture.billing_settings_before EXCEPT SELECT * FROM public.billing_settings) THEN
    RAISE EXCEPTION 'billing_settings changed';
  END IF;
END $$;

SELECT 'workspace_economics contract: passed' AS result;
