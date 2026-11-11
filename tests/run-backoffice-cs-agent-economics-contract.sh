#!/usr/bin/env bash
# Migration 429: a disposable local Postgres only; never connects to any deployed environment.
# Applies 429 twice (it must be re-runnable), checks the contract, then the rollback, then 429 once more.
set -euo pipefail
export LC_ALL="${LC_ALL:-C}"
cd "$(dirname "$0")/.."
PG_BIN="${PG_BIN:-$(dirname "$(command -v postgres || echo /opt/homebrew/opt/postgresql@15/bin/postgres)")}"
data="$(mktemp -d)"; sock="$(mktemp -d /tmp/pgs.XXXX)"; port="${PG_TEST_PORT:-55449}"
trap '"$PG_BIN/pg_ctl" -D "$data" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$data" "$sock"' EXIT
"$PG_BIN/initdb" -D "$data" -U postgres -A trust >/dev/null
"$PG_BIN/pg_ctl" -D "$data" -o "-p $port -k $sock -c listen_addresses=''" -l "$data/server.log" -w start >/dev/null || { cat "$data/server.log"; exit 1; }
run() {
  echo "Checking $1"
  # One transaction per file, as the migration runner applies them (SET LOCAL needs it).
  "$PG_BIN/psql" -X -q -h "$sock" -p "$port" -U postgres -v ON_ERROR_STOP=1 --single-transaction -f "$1"
}
run tests/fixtures/backoffice-cs-agent-economics-bootstrap.sql
run migrations/next-release/429_backoffice-cs-agent-economics.sql
run migrations/next-release/429_backoffice-cs-agent-economics.sql
run tests/backoffice-cs-agent-economics-contract.sql
run migrations/next-release/rollback/429_backoffice-cs-agent-economics.rollback.sql
"$PG_BIN/psql" -X -q -h "$sock" -p "$port" -U postgres -v ON_ERROR_STOP=1 <<'SQL'
DO $$ BEGIN
  IF to_regclass('public.workspace_economics') IS NOT NULL THEN RAISE EXCEPTION 'the rollback left workspace_economics'; END IF;
  -- The rest is untouched.
  IF to_regclass('public.organization') IS NULL OR to_regclass('public.usage') IS NULL THEN
    RAISE EXCEPTION 'the rollback removed more than 429';
  END IF;
  IF EXISTS (SELECT * FROM public.usage EXCEPT SELECT * FROM contract_fixture.usage_before)
     OR EXISTS (SELECT * FROM contract_fixture.usage_before EXCEPT SELECT * FROM public.usage) THEN
    RAISE EXCEPTION 'usage changed';
  END IF;
END $$;
SQL
echo "Checking the rollback: passed"
run migrations/next-release/429_backoffice-cs-agent-economics.sql
"$PG_BIN/psql" -X -q -h "$sock" -p "$port" -U postgres -v ON_ERROR_STOP=1 <<'SQL'
DO $$ BEGIN
  -- After the rollback, 429 creates the table again, empty.
  IF to_regclass('public.workspace_economics') IS NULL OR EXISTS (SELECT 1 FROM public.workspace_economics) THEN
    RAISE EXCEPTION 're-applying 429 did not create an empty workspace_economics';
  END IF;
END $$;
SQL
echo 'Backoffice cs agent economics contract passed.'
