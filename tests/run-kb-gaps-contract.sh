#!/usr/bin/env bash
# KB gaps (448) contract: a disposable local Postgres only; never connects to any deployed environment.
set -euo pipefail
export LC_ALL="${LC_ALL:-C}"
cd "$(dirname "$0")/.."
PG_BIN="${PG_BIN:-$(dirname "$(command -v postgres || echo /opt/homebrew/opt/postgresql@15/bin/postgres)")}"
data="$(mktemp -d)"; sock="$(mktemp -d /tmp/pgs.XXXX)"; port="${PG_TEST_PORT:-55448}"
trap '"$PG_BIN/pg_ctl" -D "$data" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$data" "$sock"' EXIT
"$PG_BIN/initdb" -D "$data" -U postgres -A trust >/dev/null
"$PG_BIN/pg_ctl" -D "$data" -o "-p $port -k $sock -c listen_addresses=''" -l "$data/server.log" -w start >/dev/null || { cat "$data/server.log"; exit 1; }
for sql in tests/fixtures/kb-gaps-bootstrap.sql \
           migrations/next-release/448_kb-gaps.sql \
           migrations/next-release/448_kb-gaps.sql \
           tests/kb-gaps-contract.sql; do
  echo "Checking $sql"
  # One transaction per file, as the migration runner applies them (SET LOCAL needs it).
  "$PG_BIN/psql" -X -q -h "$sock" -p "$port" -U postgres -v ON_ERROR_STOP=1 -1 -f "$sql"
done
echo 'KB gaps contract passed.'
