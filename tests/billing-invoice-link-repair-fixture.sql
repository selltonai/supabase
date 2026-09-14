-- Fixture for the operator repair; the runner disposes of this entire database.
INSERT INTO organization(id) VALUES ('repair-contract-a'),('repair-contract-b');
INSERT INTO billing_invoices(id, organization_id, period_start, period_end, subtotal, total, status, line_items)
VALUES ('cccccccc-cccc-4ccc-8ccc-cccccccccccc', 'repair-contract-a', '2026-09-01', '2026-09-02', 5, 5, 'paid', '[{"action":"company_research","sellton_cost":5}]'),
       ('dddddddd-dddd-4ddd-8ddd-dddddddddddd', 'repair-contract-a', '2026-09-02', '2026-09-03', 7, 7, 'paid', '[{"action":"company_research","sellton_cost":7}]');
INSERT INTO usage(id, organization_id, created_at, provider, model_name, metadata, sellton_cost)
VALUES ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'repair-contract-a', '2026-09-01T10:00:00Z', 'openai', 'gpt-4.1-mini', '{"service":"company_research"}', 5),
       ('ffffffff-ffff-4fff-8fff-ffffffffffff', 'repair-contract-a', '2026-09-02T00:00:00Z', 'openai', 'gpt-4.1-mini', '{"service":"company_research"}', 6),
       ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', 'repair-contract-b', '2026-09-01T10:00:00Z', 'openai', 'gpt-4.1-mini', '{}', 100);
