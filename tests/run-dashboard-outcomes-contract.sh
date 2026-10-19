#!/usr/bin/env bash
# KAN-322 FR-A11i / FR-A11g: a disposable local Postgres only; never connects to any deployed environment.
# 406 (dashboard_outcomes_v1) on its own bootstrap; 407 (dashboard_people_reply_rollup_v2) after 387 and v1's contract.
# Each migration runs twice (it must be re-runnable).
set -euo pipefail
export LC_ALL="${LC_ALL:-C}"
cd "$(dirname "$0")/.."
PG_BIN="${PG_BIN:-$(dirname "$(command -v postgres || echo /opt/homebrew/opt/postgresql@15/bin/postgres)")}"
data="$(mktemp -d)"; sock="$(mktemp -d /tmp/pgs.XXXX)"; port="${PG_TEST_PORT:-55441}"
trap '"$PG_BIN/pg_ctl" -D "$data" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$data" "$sock"' EXIT
"$PG_BIN/initdb" -D "$data" -U postgres -A trust >/dev/null
"$PG_BIN/pg_ctl" -D "$data" -o "-p $port -k $sock -c listen_addresses=''" -l "$data/server.log" -w start >/dev/null || { cat "$data/server.log"; exit 1; }
run() { "$PG_BIN/psql" -X -q -h "$sock" -p "$port" -U postgres -v ON_ERROR_STOP=1 -d "$1" -f "$2"; }
"$PG_BIN/createdb" -h "$sock" -p "$port" -U postgres outcomes
"$PG_BIN/createdb" -h "$sock" -p "$port" -U postgres people
# As Supabase: new public functions are executable by anon and authenticated unless revoked (407 must revoke).
"$PG_BIN/psql" -X -q -h "$sock" -p "$port" -U postgres -d people -c "DO \$\$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon; END IF; IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated; END IF; END \$\$; ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon, authenticated;" >/dev/null
for sql in tests/fixtures/dashboard-outcomes-bootstrap.sql \
           migrations/next-release/406_dashboard-outcomes-new-people-meetings-deals.sql \
           migrations/next-release/406_dashboard-outcomes-new-people-meetings-deals.sql \
           tests/dashboard-outcomes-contract.sql; do
  echo "Checking $sql (outcomes)"; run outcomes "$sql"
done
for sql in tests/fixtures/dashboard-people-bootstrap.sql \
           migrations/next-release/387_dashboard-people-and-campaign-channel-stats.sql \
           migrations/next-release/407_dashboard-people-reply-rollup-v2.sql \
           migrations/next-release/407_dashboard-people-reply-rollup-v2.sql \
           tests/dashboard-people-rollup-contract.sql \
           tests/dashboard-people-rollup-v2-contract.sql; do
  echo "Checking $sql (people)"; run people "$sql"
done
# The rollback drops both and leaves v1.
run outcomes migrations/next-release/rollback/406-407_dashboard-outcomes-and-people-v2.rollback.sql
run people migrations/next-release/rollback/406-407_dashboard-outcomes-and-people-v2.rollback.sql
"$PG_BIN/psql" -X -q -h "$sock" -p "$port" -U postgres -d people -tAc \
  "SELECT CASE WHEN to_regprocedure('public.dashboard_people_reply_rollup_v2(text,timestamptz,timestamptz,text)') IS NULL
               AND to_regprocedure('public.dashboard_people_reply_rollup_v1(text,timestamptz,timestamptz,text)') IS NOT NULL
          THEN 'rollback ok' ELSE 'rollback FAILED' END" | grep -q 'rollback ok' || { echo 'rollback check failed'; exit 1; }
echo 'Dashboard outcomes (406) and people v2 (407) contracts passed.'
