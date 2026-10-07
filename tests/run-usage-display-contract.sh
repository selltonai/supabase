#!/usr/bin/env bash
# KAN-322 FR-A12: a disposable local Postgres only; never connects to any deployed environment.
set -euo pipefail
export LC_ALL="${LC_ALL:-C}"
cd "$(dirname "$0")/.."
PG_BIN="${PG_BIN:-$(dirname "$(command -v postgres || echo /opt/homebrew/opt/postgresql@15/bin/postgres)")}"
data="$(mktemp -d)"; sock="$(mktemp -d /tmp/pgs.XXXX)"; port="${PG_TEST_PORT:-55440}"; helpers="$(mktemp)"
trap '"$PG_BIN/pg_ctl" -D "$data" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$data" "$sock" "$helpers"' EXIT
"$PG_BIN/initdb" -D "$data" -U postgres -A trust >/dev/null
"$PG_BIN/pg_ctl" -D "$data" -o "-p $port -k $sock -c listen_addresses=''" -l "$data/server.log" -w start >/dev/null || { cat "$data/server.log"; exit 1; }
# 345 calls 326's usage_metadata_* and usage_provider_label helpers; take them from 326 itself rather than a copy.
awk '/^CREATE OR REPLACE FUNCTION public.usage_(metadata_[a-z]+|provider_label)\(/,/^\$\$;/' \
  migrations/release_1.2.0/326_speed-up-usage-billing-pages.sql > "$helpers"
for sql in tests/fixtures/usage-display-bootstrap.sql \
           "$helpers" \
           migrations/release_1.3.0/345_usage-analytics-projection.sql \
           migrations/next-release/388_usage-display-categories.sql \
           migrations/next-release/388_usage-display-categories.sql \
           tests/usage-display-categories-contract.sql; do
  echo "Checking $sql"
  "$PG_BIN/psql" -X -q -h "$sock" -p "$port" -U postgres -v ON_ERROR_STOP=1 -f "$sql"
done
echo 'Usage display categories contract passed.'
