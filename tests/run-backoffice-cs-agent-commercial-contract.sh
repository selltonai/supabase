#!/usr/bin/env bash
# Migration 427: a disposable local Postgres only; never connects to any deployed environment.
# Applies 422, then 427 twice (it must be re-runnable), checks the contract, then the rollback, then 427 once more.
set -euo pipefail
export LC_ALL="${LC_ALL:-C}"
cd "$(dirname "$0")/.."
PG_BIN="${PG_BIN:-$(dirname "$(command -v postgres || echo /opt/homebrew/opt/postgresql@15/bin/postgres)")}"
data="$(mktemp -d)"; sock="$(mktemp -d /tmp/pgs.XXXX)"; port="${PG_TEST_PORT:-55447}"
trap '"$PG_BIN/pg_ctl" -D "$data" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$data" "$sock"' EXIT
"$PG_BIN/initdb" -D "$data" -U postgres -A trust >/dev/null
"$PG_BIN/pg_ctl" -D "$data" -o "-p $port -k $sock -c listen_addresses=''" -l "$data/server.log" -w start >/dev/null || { cat "$data/server.log"; exit 1; }
run() {
  echo "Checking $1"
  # One transaction per file, as the migration runner applies them (SET LOCAL needs it).
  "$PG_BIN/psql" -X -q -h "$sock" -p "$port" -U postgres -v ON_ERROR_STOP=1 --single-transaction -f "$1"
}
run tests/fixtures/backoffice-cs-agent-commercial-bootstrap.sql
run migrations/next-release/422_backoffice-cs-agent-core.sql
run migrations/next-release/427_backoffice-cs-agent-commercial.sql
run migrations/next-release/427_backoffice-cs-agent-commercial.sql
run tests/backoffice-cs-agent-commercial-contract.sql
run migrations/next-release/rollback/427_backoffice-cs-agent-commercial.rollback.sql
"$PG_BIN/psql" -X -q -h "$sock" -p "$port" -U postgres -v ON_ERROR_STOP=1 <<'SQL'
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['workspace_plans', 'workspace_price_overrides', 'workspace_allowances', 'seat_discounts',
                           'trial_policies', 'discount_policies', 'connection_ledger', 'workspace_company_profile',
                           'cs_customer_signals', 'cs_brain_cursor'] LOOP
    IF to_regclass('public.' || t) IS NOT NULL THEN RAISE EXCEPTION 'the rollback left %', t; END IF;
  END LOOP;
  -- 422 and billing_settings are untouched.
  IF to_regclass('public.cs_recommendations') IS NULL THEN RAISE EXCEPTION 'the rollback removed more than 427'; END IF;
  IF EXISTS (SELECT * FROM public.billing_settings EXCEPT SELECT * FROM contract_fixture.billing_settings_before)
     OR EXISTS (SELECT * FROM contract_fixture.billing_settings_before EXCEPT SELECT * FROM public.billing_settings) THEN
    RAISE EXCEPTION 'billing_settings changed';
  END IF;
END $$;
SQL
echo "Checking the rollback: passed"
run migrations/next-release/427_backoffice-cs-agent-commercial.sql
"$PG_BIN/psql" -X -q -h "$sock" -p "$port" -U postgres -v ON_ERROR_STOP=1 <<'SQL'
DO $$ BEGIN
  -- After the rollback, 427 seeds its policy rows again, once.
  IF (SELECT count(*) FROM public.trial_policies) <> 2 OR (SELECT count(*) FROM public.discount_policies) <> 1 THEN
    RAISE EXCEPTION 're-applying 427 did not seed the policy rows once';
  END IF;
END $$;
SQL
echo 'Backoffice cs agent commercial contract passed.'
