#!/usr/bin/env bash
# Migration 432: a disposable local Postgres only; never connects to any deployed environment.
# Applies 422, 423 and 427, keeps 423's two function definitions, applies 432 twice (it must be re-runnable), checks
# the contract, then the rollback (423's definitions exactly, and 423's own contract passes), then 432 once more.
set -euo pipefail
export LC_ALL="${LC_ALL:-C}"
cd "$(dirname "$0")/.."
PG_BIN="${PG_BIN:-$(dirname "$(command -v postgres || echo /opt/homebrew/opt/postgresql@15/bin/postgres)")}"
data="$(mktemp -d)"; sock="$(mktemp -d /tmp/pgs.XXXX)"; port="${PG_TEST_PORT:-55451}"
trap '"$PG_BIN/pg_ctl" -D "$data" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$data" "$sock"' EXIT
"$PG_BIN/initdb" -D "$data" -U postgres -A trust >/dev/null
"$PG_BIN/pg_ctl" -D "$data" -o "-p $port -k $sock -c listen_addresses=''" -l "$data/server.log" -w start >/dev/null || { cat "$data/server.log"; exit 1; }
run() {
  echo "Checking $1"
  # One transaction per file, as the migration runner applies them (SET LOCAL needs it).
  "$PG_BIN/psql" -X -q -h "$sock" -p "$port" -U postgres -v ON_ERROR_STOP=1 --single-transaction -f "$1"
}
run tests/fixtures/backoffice-cs-agent-facts-bootstrap.sql
run tests/fixtures/backoffice-cs-agent-trial-facts-bootstrap.sql
run migrations/next-release/422_backoffice-cs-agent-core.sql
run migrations/next-release/423_backoffice-cs-agent-facts.sql
"$PG_BIN/psql" -X -q -h "$sock" -p "$port" -U postgres -v ON_ERROR_STOP=1 <<'SQL'
INSERT INTO contract_432.functions_423 (signature, definition, comment, acl)
SELECT s, pg_get_functiondef(to_regprocedure(s)), obj_description(to_regprocedure(s), 'pg_proc'),
       (SELECT proacl::text FROM pg_proc WHERE oid = to_regprocedure(s))
FROM unnest(ARRAY['public.backoffice_cs_segment_inputs_v1()', 'public.backoffice_cs_workspace_facts_v1(text)']) s;
SQL
run migrations/next-release/427_backoffice-cs-agent-commercial.sql
run migrations/next-release/432_backoffice-cs-agent-trial-facts.sql
run migrations/next-release/432_backoffice-cs-agent-trial-facts.sql
run tests/backoffice-cs-agent-trial-facts-contract.sql
run migrations/next-release/rollback/432_backoffice-cs-agent-trial-facts.rollback.sql
"$PG_BIN/psql" -X -q -h "$sock" -p "$port" -U postgres -v ON_ERROR_STOP=1 <<'SQL'
DO $$
DECLARE c record;
BEGIN
  FOR c IN SELECT * FROM contract_432.functions_423 LOOP
    IF pg_get_functiondef(to_regprocedure(c.signature)) IS DISTINCT FROM c.definition THEN
      RAISE EXCEPTION 'the rollback did not restore 423''s definition of %', c.signature;
    END IF;
    IF obj_description(to_regprocedure(c.signature), 'pg_proc') IS DISTINCT FROM c.comment THEN
      RAISE EXCEPTION 'the rollback did not restore 423''s comment on %', c.signature;
    END IF;
    IF (SELECT proacl::text FROM pg_proc WHERE oid = to_regprocedure(c.signature)) IS DISTINCT FROM c.acl THEN
      RAISE EXCEPTION 'the rollback did not restore 423''s grants on %', c.signature;
    END IF;
  END LOOP;
  -- 427 and the tables are untouched.
  IF to_regclass('public.workspace_allowances') IS NULL OR to_regclass('public.cs_recommendations') IS NULL THEN
    RAISE EXCEPTION 'the rollback removed more than 432';
  END IF;
END $$;
SQL
echo "Checking the rollback: passed"
run tests/backoffice-cs-agent-facts-contract.sql
run migrations/next-release/432_backoffice-cs-agent-trial-facts.sql
echo 'Backoffice cs agent trial facts contract passed.'
