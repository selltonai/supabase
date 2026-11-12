-- Migration 432's contract bootstrap, run after 423's (tests/fixtures/backoffice-cs-agent-facts-bootstrap.sql): the
-- organization columns 382 adds that 432 reads. 422, 423 and 427 are then applied as they are. Disposable database only.
ALTER TABLE public.organization
  ADD COLUMN IF NOT EXISTS web_billing_started_at timestamptz,
  ADD COLUMN IF NOT EXISTS mobile_billing_started_at timestamptz;

-- 423's two functions as 423 leaves them, filled in by the runner right after 423: the rollback must restore these.
CREATE SCHEMA IF NOT EXISTS contract_432;
CREATE TABLE contract_432.functions_423 (
  signature text PRIMARY KEY,
  definition text NOT NULL,
  comment text,
  acl text
);
