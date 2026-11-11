#!/usr/bin/env bash
# Migration 428: a disposable local Postgres only; never connects to any deployed environment.
# Applies 428 twice (it must be re-runnable), checks the contract, then the rollback, then 428 once more.
set -euo pipefail
export LC_ALL="${LC_ALL:-C}"
cd "$(dirname "$0")/.."
PG_BIN="${PG_BIN:-$(dirname "$(command -v postgres || echo /opt/homebrew/opt/postgresql@15/bin/postgres)")}"
data="$(mktemp -d)"; sock="$(mktemp -d /tmp/pgs.XXXX)"; port="${PG_TEST_PORT:-55448}"
trap '"$PG_BIN/pg_ctl" -D "$data" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$data" "$sock"' EXIT
"$PG_BIN/initdb" -D "$data" -U postgres -A trust >/dev/null
"$PG_BIN/pg_ctl" -D "$data" -o "-p $port -k $sock -c listen_addresses=''" -l "$data/server.log" -w start >/dev/null || { cat "$data/server.log"; exit 1; }
run() {
  echo "Checking $1"
  # One transaction per file, as the migration runner applies them (SET LOCAL needs it).
  "$PG_BIN/psql" -X -q -h "$sock" -p "$port" -U postgres -v ON_ERROR_STOP=1 --single-transaction -f "$1"
}
run tests/fixtures/backoffice-cs-agent-deletion-bootstrap.sql
run migrations/next-release/428_backoffice-cs-agent-deletion.sql
run migrations/next-release/428_backoffice-cs-agent-deletion.sql
run tests/backoffice-cs-agent-deletion-contract.sql
run migrations/next-release/rollback/428_backoffice-cs-agent-deletion.rollback.sql
"$PG_BIN/psql" -X -q -h "$sock" -p "$port" -U postgres -v ON_ERROR_STOP=1 <<'SQL'
DO $$ BEGIN
  IF to_regclass('public.workspace_deletions') IS NOT NULL THEN RAISE EXCEPTION 'the rollback left workspace_deletions'; END IF;
  -- The rest is untouched.
  IF to_regclass('public.organization') IS NULL OR to_regprocedure('public.update_updated_at_column()') IS NULL THEN
    RAISE EXCEPTION 'the rollback removed more than 428';
  END IF;
END $$;
SQL
echo "Checking the rollback: passed"
run migrations/next-release/428_backoffice-cs-agent-deletion.sql
echo 'Backoffice cs agent deletion contract passed.'
