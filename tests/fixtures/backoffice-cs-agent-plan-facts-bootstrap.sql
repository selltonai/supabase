-- Migration 434's contract bootstrap, run after 423's and 432's (tests/fixtures/backoffice-cs-agent-facts-bootstrap.sql,
-- tests/fixtures/backoffice-cs-agent-trial-facts-bootstrap.sql). 422, 423, 427 and 432 are then applied as they are.
-- Disposable database only.

-- 432's two functions as 432 leaves them, filled in by the runner right after 432: the facts function is the one the
-- rollback must restore, and the contract compares 434's output with it; the rollup must not change at all.
CREATE SCHEMA IF NOT EXISTS contract_434;
CREATE TABLE contract_434.functions_432 (
  signature text PRIMARY KEY,
  definition text NOT NULL,
  comment text,
  acl text
);
