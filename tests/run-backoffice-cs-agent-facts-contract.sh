#!/usr/bin/env bash
# Migration 423: a disposable local Postgres only; never connects to any deployed environment.
# Applies 422, then 423 twice (it must be re-runnable), checks the contract, then the rollback, then 423 once more.
set -euo pipefail
export LC_ALL="${LC_ALL:-C}"
cd "$(dirname "$0")/.."
PG_BIN="${PG_BIN:-$(dirname "$(command -v postgres || echo /opt/homebrew/opt/postgresql@15/bin/postgres)")}"
data="$(mktemp -d)"; sock="$(mktemp -d /tmp/pgs.XXXX)"; port="${PG_TEST_PORT:-55443}"
trap '"$PG_BIN/pg_ctl" -D "$data" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$data" "$sock"' EXIT
"$PG_BIN/initdb" -D "$data" -U postgres -A trust >/dev/null
"$PG_BIN/pg_ctl" -D "$data" -o "-p $port -k $sock -c listen_addresses=''" -l "$data/server.log" -w start >/dev/null || { cat "$data/server.log"; exit 1; }
run() {
  echo "Checking $1"
  # One transaction per file, as the migration runner applies them (SET LOCAL needs it).
  "$PG_BIN/psql" -X -q -h "$sock" -p "$port" -U postgres -v ON_ERROR_STOP=1 --single-transaction -f "$1"
}
run tests/fixtures/backoffice-cs-agent-facts-bootstrap.sql
run migrations/next-release/422_backoffice-cs-agent-core.sql
run migrations/next-release/423_backoffice-cs-agent-facts.sql
run migrations/next-release/423_backoffice-cs-agent-facts.sql
run tests/backoffice-cs-agent-facts-contract.sql
run migrations/next-release/rollback/423_backoffice-cs-agent-facts.rollback.sql
"$PG_BIN/psql" -X -q -h "$sock" -p "$port" -U postgres -v ON_ERROR_STOP=1 <<'SQL'
DO $$ BEGIN
  IF to_regprocedure('public.backoffice_cs_segment_inputs_v1()') IS NOT NULL
     OR to_regprocedure('public.backoffice_cs_workspace_facts_v1(text)') IS NOT NULL THEN
    RAISE EXCEPTION 'the rollback left a function';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema = 'public' AND table_name = 'user_profiles'
               AND column_name IN ('last_seen_at', 'consent_marketing_at')) THEN
    RAISE EXCEPTION 'the rollback left a user_profiles column';
  END IF;
  -- 422 and the rest of user_profiles are untouched.
  IF to_regclass('public.cs_recommendations') IS NULL OR NOT EXISTS (
       SELECT 1 FROM information_schema.columns
       WHERE table_schema = 'public' AND table_name = 'user_profiles' AND column_name = 'ui_seen') THEN
    RAISE EXCEPTION 'the rollback removed more than 423';
  END IF;
END $$;
SQL
echo "Checking the rollback: passed"
run migrations/next-release/423_backoffice-cs-agent-facts.sql
echo 'Backoffice cs agent facts contract passed.'
