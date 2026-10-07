#!/usr/bin/env bash
# S10 / migration 390: a disposable local Postgres only; never connects to any deployed environment.
set -euo pipefail
export LC_ALL="${LC_ALL:-C}"
cd "$(dirname "$0")/.."
PG_BIN="${PG_BIN:-$(dirname "$(command -v postgres || echo /opt/homebrew/opt/postgresql@15/bin/postgres)")}"
data="$(mktemp -d)"; sock="$(mktemp -d /tmp/pgs.XXXX)"; port="${PG_TEST_PORT:-55441}"
trap '"$PG_BIN/pg_ctl" -D "$data" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$data" "$sock"' EXIT
"$PG_BIN/initdb" -D "$data" -U postgres -A trust >/dev/null
"$PG_BIN/pg_ctl" -D "$data" -o "-p $port -k $sock -c listen_addresses=''" -l "$data/server.log" -w start >/dev/null || { cat "$data/server.log"; exit 1; }
psql_db() { "$PG_BIN/psql" -X -q -h "$sock" -p "$port" -U postgres -v ON_ERROR_STOP=1 -d "$1" "${@:2}"; }
migration=migrations/next-release/390_revoke-public-execute-on-internal-functions.sql

# 1. The migration applies, is idempotent, and leaves the contract true.
for sql in tests/fixtures/revoke-internal-functions-bootstrap.sql "$migration" "$migration" tests/revoke-internal-functions-contract.sql; do
  echo "Checking $sql"
  psql_db postgres -f "$sql"
done

# 2. Fail loud: if anon can still execute through another path (here: a role it is a member of), the migration
#    raises and its transaction rolls back, instead of reporting success.
psql_db postgres -c "CREATE DATABASE fail_loud"
psql_db fail_loud -f tests/fixtures/revoke-internal-functions-bootstrap.sql
psql_db fail_loud -c "CREATE ROLE leaky; GRANT leaky TO anon; GRANT EXECUTE ON FUNCTION public.get_organization_summary(text) TO leaky;"
if psql_db fail_loud -1 -f "$migration" 2>"$data/fail.log"; then
  echo "The migration should have failed while anon can still execute through a role"; exit 1
fi
grep -Eq "390: anon or authenticated can still execute: (public\.)?get_organization_summary\(text\)" "$data/fail.log" || { cat "$data/fail.log"; exit 1; }
# Rolled back: the earlier revokes in the same run did not stick.
[ "$(psql_db fail_loud -At -c "SELECT has_function_privilege('anon', 'public.claim_due_sequence_actions(timestamptz,timestamptz,integer)', 'EXECUTE')")" = "t" ] \
  || { echo "A failed run must roll back"; exit 1; }

echo 'Revoke internal functions contract passed.'
