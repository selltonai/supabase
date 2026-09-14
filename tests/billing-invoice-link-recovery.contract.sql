-- Disposable database only, after migrations 243, 326, 345, and 370.
BEGIN;
SET LOCAL TIME ZONE 'UTC';
INSERT INTO organization(id) VALUES ('billing-contract-a'), ('billing-contract-b');
INSERT INTO billing_invoices(id, organization_id, period_start, period_end, subtotal, total, status, usage_link_state)
VALUES ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', 'billing-contract-a', '2026-09-07', '2026-09-14', 1100, 1112, 'paid', 'pending');
INSERT INTO usage(id, organization_id, created_at, provider, model_name, metadata, sellton_cost, total_tokens)
SELECT md5('billing-row-' || i)::uuid, 'billing-contract-a', '2026-09-08T10:00:00Z',
       'openai', 'gpt-4.1-mini', '{"service":"company_research"}', 1, 1
FROM generate_series(1,1100) i;
INSERT INTO usage(organization_id, created_at, provider, model_name, metadata, sellton_cost)
VALUES ('billing-contract-b', '2026-09-08T10:00:00Z', 'openai', 'gpt-4.1-mini', '{}', 999),
       ('billing-contract-a', '2026-09-14T00:00:00Z', 'openai', 'gpt-4.1-mini', '{}', 20),
       ('billing-contract-a', '2026-09-08T12:00:00Z', 'openai', 'gpt-4.1-mini', '{}', 30);

DO $$
DECLARE amount numeric;
BEGIN
  SELECT sum(total_sellton_cost) INTO amount FROM billing_usage_for_period_v1('billing-contract-a', '2026-09-07', '2026-09-14', true);
  IF amount <> 1130 THEN RAISE EXCEPTION 'tenant, row-cap, or weekly cutoff failure: %', amount; END IF;
  SELECT sum(total_sellton_cost) INTO amount FROM billing_usage_for_period_v1('billing-contract-a', '2026-09-08T10:00:00Z', '2026-09-08T12:00:00Z', true);
  IF amount <> 1100 THEN RAISE EXCEPTION 'intraday half-open boundary failure: %', amount; END IF;
  IF has_function_privilege('authenticated', 'public.billing_usage_for_period_v1(text,timestamptz,timestamptz,boolean)', 'execute') OR has_function_privilege('anon', 'public.billing_usage_for_period_v1(text,timestamptz,timestamptz,boolean)', 'execute') THEN
    RAISE EXCEPTION 'billing aggregation exposed to public roles';
  END IF;
  IF NOT has_function_privilege('service_role', 'public.billing_usage_for_period_v1(text,timestamptz,timestamptz,boolean)', 'execute') THEN
    RAISE EXCEPTION 'service role cannot execute billing aggregation';
  END IF;
END $$;

CREATE TEMP TABLE before_contributions AS SELECT usage_id, ctid::text AS tuple_id, to_jsonb(c) AS data FROM usage_analytics_projection_contributions c;
CREATE TEMP TABLE before_rollups AS SELECT ctid::text AS tuple_id, to_jsonb(r) AS data FROM usage_analytics_projection_rollups r;
SET LOCAL statement_timeout = '8s';
UPDATE usage SET invoice_id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
WHERE organization_id = 'billing-contract-a' AND created_at = '2026-09-08T10:00:00Z';

DO $$
DECLARE amount numeric;
BEGIN
  IF EXISTS (SELECT 1 FROM usage_analytics_projection_contributions c JOIN before_contributions b USING (usage_id) WHERE c.ctid::text <> b.tuple_id OR to_jsonb(c) <> b.data) THEN
    RAISE EXCEPTION 'invoice-only update rewrote an analytics contribution';
  END IF;
  IF EXISTS ((SELECT ctid::text, to_jsonb(r) FROM usage_analytics_projection_rollups r EXCEPT SELECT tuple_id, data FROM before_rollups) UNION ALL (SELECT tuple_id,data FROM before_rollups EXCEPT SELECT ctid::text,to_jsonb(r) FROM usage_analytics_projection_rollups r)) THEN
    RAISE EXCEPTION 'invoice-only update rewrote an analytics rollup';
  END IF;
  SELECT sum(total_sellton_cost) INTO amount FROM billing_usage_for_period_v1('billing-contract-a', '2026-09-07', '2026-09-14', true);
  IF amount <> 30 THEN RAISE EXCEPTION 'linked usage is still uninvoiced: %', amount; END IF;
  SELECT sum(total_sellton_cost) INTO amount FROM billing_usage_for_period_v1('billing-contract-a', '2026-09-07', '2026-09-14', false);
  IF amount <> 1130 THEN RAISE EXCEPTION 'monthly usage changed because invoice linkage changed: %', amount; END IF;
END $$;

-- A simultaneous billing and cost correction must still update analytics.
UPDATE usage SET invoice_id = NULL, sellton_cost = 2 WHERE id = md5('billing-row-1')::uuid;
DO $$
BEGIN
  IF (SELECT sellton_cost FROM usage_analytics_projection_contributions WHERE usage_id = md5('billing-row-1')::uuid) <> 2 THEN
    RAISE EXCEPTION 'mixed cost/invoice update skipped analytics';
  END IF;
END $$;

-- Old code defaults to legacy: rolling deployment never invents recoverable claims.
INSERT INTO billing_invoices(organization_id, period_start, period_end)
VALUES ('billing-contract-b', '2026-09-07', '2026-09-14');
DO $$
BEGIN
  IF (SELECT usage_link_state FROM billing_invoices WHERE organization_id = 'billing-contract-b') <> 'legacy' THEN
    RAISE EXCEPTION 'legacy invoice default changed';
  END IF;
END $$;
ROLLBACK;
