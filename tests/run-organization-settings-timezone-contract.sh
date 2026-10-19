#!/usr/bin/env bash
# KAN-322 FR-C8b: a disposable local Postgres only; never connects to any deployed environment.
set -euo pipefail
export LC_ALL="${LC_ALL:-C}"
cd "$(dirname "$0")/.."
PG_BIN="${PG_BIN:-$(dirname "$(command -v postgres || echo /opt/homebrew/opt/postgresql@15/bin/postgres)")}"
data="$(mktemp -d)"; sock="$(mktemp -d /tmp/pgs.XXXX)"; port="${PG_TEST_PORT:-55449}"
trap '"$PG_BIN/pg_ctl" -D "$data" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$data" "$sock"' EXIT
"$PG_BIN/initdb" -D "$data" -U postgres -A trust >/dev/null
"$PG_BIN/pg_ctl" -D "$data" -o "-p $port -k $sock -c listen_addresses=''" -l "$data/server.log" -w start >/dev/null || { cat "$data/server.log"; exit 1; }
for sql in tests/fixtures/organization-settings-timezone-bootstrap.sql \
           migrations/next-release/409_organization-settings-timezone.sql \
           migrations/next-release/409_organization-settings-timezone.sql \
           tests/organization-settings-timezone-contract.sql \
           migrations/next-release/rollback/409_organization-settings-timezone.rollback.sql \
           tests/organization-settings-timezone-rollback-check.sql \
           migrations/next-release/409_organization-settings-timezone.sql \
           tests/organization-settings-timezone-contract.sql; do
  echo "Checking $sql"
  "$PG_BIN/psql" -X -q -h "$sock" -p "$port" -U postgres -v ON_ERROR_STOP=1 -f "$sql"
done
echo 'Organization settings timezone contract passed.'
