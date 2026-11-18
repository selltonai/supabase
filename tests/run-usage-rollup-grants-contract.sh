#!/usr/bin/env bash
# Migration 440: a disposable local Postgres only; never connects to any deployed environment.
set -euo pipefail
export LC_ALL="${LC_ALL:-C}"
cd "$(dirname "$0")/.."
PG_BIN="${PG_BIN:-$(dirname "$(command -v postgres || echo /opt/homebrew/opt/postgresql@15/bin/postgres)")}"
data="$(mktemp -d)"; sock="$(mktemp -d /tmp/pgs.XXXX)"; port="${PG_TEST_PORT:-55440}"
trap '"$PG_BIN/pg_ctl" -D "$data" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$data" "$sock"' EXIT
"$PG_BIN/initdb" -D "$data" -U postgres -A trust >/dev/null
"$PG_BIN/pg_ctl" -D "$data" -o "-p $port -k $sock -c listen_addresses=''" -l "$data/server.log" -w start >/dev/null || { cat "$data/server.log"; exit 1; }
# 440 twice: it must be safe to re-run. Each file runs in one transaction, as the migration runner does.
for sql in tests/fixtures/usage-rollup-grants-bootstrap.sql \
           migrations/next-release/440_close-usage-rollup-and-week-snapshot-to-browser-key.sql \
           migrations/next-release/440_close-usage-rollup-and-week-snapshot-to-browser-key.sql \
           tests/usage-rollup-grants-contract.sql; do
  echo "Checking $sql"
  case "$sql" in
    migrations/*) "$PG_BIN/psql" -X -q -h "$sock" -p "$port" -U postgres -v ON_ERROR_STOP=1 -1 -f "$sql" ;;
    *)            "$PG_BIN/psql" -X -q -h "$sock" -p "$port" -U postgres -v ON_ERROR_STOP=1 -f "$sql" ;;
  esac
done
echo 'Usage rollup grants contract passed.'
