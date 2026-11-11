#!/usr/bin/env bash
# Migration 422: a disposable local Postgres only; never connects to any deployed environment.
# Applies 422 twice (it must be re-runnable), checks the contract, then the rollback, then 422 once more.
set -euo pipefail
export LC_ALL="${LC_ALL:-C}"
cd "$(dirname "$0")/.."
PG_BIN="${PG_BIN:-$(dirname "$(command -v postgres || echo /opt/homebrew/opt/postgresql@15/bin/postgres)")}"
data="$(mktemp -d)"; sock="$(mktemp -d /tmp/pgs.XXXX)"; port="${PG_TEST_PORT:-55442}"
trap '"$PG_BIN/pg_ctl" -D "$data" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$data" "$sock"' EXIT
"$PG_BIN/initdb" -D "$data" -U postgres -A trust >/dev/null
"$PG_BIN/pg_ctl" -D "$data" -o "-p $port -k $sock -c listen_addresses=''" -l "$data/server.log" -w start >/dev/null || { cat "$data/server.log"; exit 1; }
run() {
  echo "Checking $1"
  # One transaction per file, as the migration runner applies them (SET LOCAL needs it).
  "$PG_BIN/psql" -X -q -h "$sock" -p "$port" -U postgres -v ON_ERROR_STOP=1 --single-transaction -f "$1"
}
run tests/fixtures/backoffice-cs-agent-core-bootstrap.sql
run migrations/next-release/422_backoffice-cs-agent-core.sql
run migrations/next-release/422_backoffice-cs-agent-core.sql
run tests/backoffice-cs-agent-core-contract.sql
run migrations/next-release/rollback/422_backoffice-cs-agent-core.rollback.sql
"$PG_BIN/psql" -X -q -h "$sock" -p "$port" -U postgres -v ON_ERROR_STOP=1 <<'SQL'
DO $$ BEGIN
  IF to_regclass('public.cs_threads') IS NOT NULL OR to_regclass('public.cs_recommendations') IS NOT NULL
     OR to_regclass('public.cs_costs') IS NOT NULL THEN
    RAISE EXCEPTION 'the rollback left a table';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema = 'public' AND table_name = 'email_sequence_steps' AND column_name = 'signup_source') THEN
    RAISE EXCEPTION 'the rollback left signup_source';
  END IF;
  -- The two steps on the new audiences are off and back on not_activated; the two original steps are as they were.
  IF EXISTS (SELECT 1 FROM public.email_sequence_steps WHERE step_key IN ('chase-stuck', 'segment-phone')
             AND (is_active OR audience_mode <> 'not_activated')) THEN
    RAISE EXCEPTION 'the rollback left a step on a removed audience, or active';
  END IF;
  IF (SELECT count(*) FROM public.email_sequence_steps WHERE step_key IN ('pending-24h', 'funnel-72h') AND is_active) <> 2 THEN
    RAISE EXCEPTION 'the rollback changed an original step';
  END IF;
END $$;
SQL
echo "Checking the rollback: passed"
run migrations/next-release/422_backoffice-cs-agent-core.sql
echo 'Backoffice cs agent core contract passed.'
