#!/usr/bin/env bash
# Migration 451: a disposable local Postgres only; never connects to any deployed environment.
set -euo pipefail
export LC_ALL="${LC_ALL:-C}"
cd "$(dirname "$0")/.."
PG_BIN="${PG_BIN:-$(dirname "$(command -v postgres || echo /opt/homebrew/opt/postgresql@15/bin/postgres)")}"
data="$(mktemp -d)"; sock="$(mktemp -d /tmp/pgs.XXXX)"; port="${PG_TEST_PORT:-55451}"
trap '"$PG_BIN/pg_ctl" -D "$data" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$data" "$sock"' EXIT
"$PG_BIN/initdb" -D "$data" -U postgres -A trust >/dev/null
"$PG_BIN/pg_ctl" -D "$data" -o "-p $port -k $sock -c listen_addresses=''" -l "$data/server.log" -w start >/dev/null || { cat "$data/server.log"; exit 1; }
# 451 twice: it must be safe to re-run.
for sql in tests/fixtures/customer-requests-bootstrap.sql \
           migrations/next-release/391_customer-requests.sql \
           migrations/next-release/439_customer-requests-trial-extension.sql \
           migrations/next-release/451_customer-requests-switch-to-full.sql \
           migrations/next-release/451_customer-requests-switch-to-full.sql \
           tests/customer-requests-contract.sql \
           tests/customer-requests-switch-to-full-contract.sql; do
  echo "Checking $sql"
  "$PG_BIN/psql" -X -q -h "$sock" -p "$port" -U postgres -v ON_ERROR_STOP=1 -f "$sql"
done
echo 'Customer requests switch_to_full contract passed.'
