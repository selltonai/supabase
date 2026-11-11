#!/usr/bin/env bash
# Migration 433: a disposable local Postgres only; never connects to any deployed environment.
# Applies 433 twice (it must be re-runnable), checks the contract, then the rollback, then 433 once more.
set -euo pipefail
export LC_ALL="${LC_ALL:-C}"
cd "$(dirname "$0")/.."
PG_BIN="${PG_BIN:-$(dirname "$(command -v postgres || echo /opt/homebrew/opt/postgresql@15/bin/postgres)")}"
data="$(mktemp -d)"; sock="$(mktemp -d /tmp/pgs.XXXX)"; port="${PG_TEST_PORT:-55452}"
trap '"$PG_BIN/pg_ctl" -D "$data" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$data" "$sock"' EXIT
"$PG_BIN/initdb" -D "$data" -U postgres -A trust >/dev/null
"$PG_BIN/pg_ctl" -D "$data" -o "-p $port -k $sock -c listen_addresses=''" -l "$data/server.log" -w start >/dev/null || { cat "$data/server.log"; exit 1; }
run() {
  echo "Checking $1"
  # One transaction per file, as the migration runner applies them.
  "$PG_BIN/psql" -X -q -h "$sock" -p "$port" -U postgres -v ON_ERROR_STOP=1 --single-transaction -f "$1"
}
run tests/fixtures/backoffice-cs-agent-settings-bootstrap.sql
run migrations/next-release/433_backoffice-cs-agent-settings.sql
run migrations/next-release/433_backoffice-cs-agent-settings.sql
run tests/backoffice-cs-agent-settings-contract.sql
run migrations/next-release/rollback/433_backoffice-cs-agent-settings.rollback.sql
"$PG_BIN/psql" -X -q -h "$sock" -p "$port" -U postgres -v ON_ERROR_STOP=1 <<'SQL'
DO $$ BEGIN
  IF to_regclass('public.cs_settings') IS NOT NULL OR to_regclass('public.cs_settings_history') IS NOT NULL THEN
    RAISE EXCEPTION 'the rollback left cs_settings or its history';
  END IF;
  IF to_regprocedure('public.cs_settings_touch()') IS NOT NULL
     OR to_regprocedure('public.cs_settings_record_history()') IS NOT NULL
     OR to_regprocedure('public.cs_settings_history_append_only()') IS NOT NULL THEN
    RAISE EXCEPTION 'the rollback left a cs_settings function';
  END IF;
  -- The rest is untouched.
  IF to_regclass('public.billing_settings') IS NULL THEN RAISE EXCEPTION 'the rollback removed more than 433'; END IF;
  IF EXISTS (SELECT * FROM public.billing_settings EXCEPT SELECT * FROM contract_fixture.billing_settings_before)
     OR EXISTS (SELECT * FROM contract_fixture.billing_settings_before EXCEPT SELECT * FROM public.billing_settings) THEN
    RAISE EXCEPTION 'billing_settings changed';
  END IF;
END $$;
SQL
echo "Checking the rollback: passed"
run migrations/next-release/433_backoffice-cs-agent-settings.sql
"$PG_BIN/psql" -X -q -h "$sock" -p "$port" -U postgres -v ON_ERROR_STOP=1 <<'SQL'
DO $$ BEGIN
  -- After the rollback, 433 creates both tables again, empty.
  IF to_regclass('public.cs_settings') IS NULL OR EXISTS (SELECT 1 FROM public.cs_settings)
     OR to_regclass('public.cs_settings_history') IS NULL OR EXISTS (SELECT 1 FROM public.cs_settings_history) THEN
    RAISE EXCEPTION 're-applying 433 did not create empty cs_settings tables';
  END IF;
END $$;
SQL
echo 'Backoffice cs agent settings contract passed.'
