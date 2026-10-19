#!/usr/bin/env bash
# KAN-322 FR-B5e: a disposable local Postgres only; never connects to any deployed environment.
set -euo pipefail
export LC_ALL="${LC_ALL:-C}"
cd "$(dirname "$0")/.."
PG_BIN="${PG_BIN:-$(dirname "$(command -v postgres || echo /opt/homebrew/opt/postgresql@15/bin/postgres)")}"
data="$(mktemp -d)"; sock="$(mktemp -d /tmp/pgs.XXXX)"; port="${PG_TEST_PORT:-55441}"
trap '"$PG_BIN/pg_ctl" -D "$data" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$data" "$sock"' EXIT
"$PG_BIN/initdb" -D "$data" -U postgres -A trust >/dev/null
"$PG_BIN/pg_ctl" -D "$data" -o "-p $port -k $sock -c listen_addresses=''" -l "$data/server.log" -w start >/dev/null || { cat "$data/server.log"; exit 1; }
# 408 twice: it must be re-runnable. The rollback, then 408 again: the rollback must drop exactly v2.
for sql in tests/fixtures/task-stats-counts-bootstrap.sql \
           migrations/next-release/386_task-stats-counts-rpc.sql \
           migrations/next-release/408_task-stats-counts-v2.sql \
           migrations/next-release/408_task-stats-counts-v2.sql \
           migrations/next-release/rollback/408_task-stats-counts-v2.rollback.sql \
           migrations/next-release/408_task-stats-counts-v2.sql \
           tests/task-stats-counts-v2-contract.sql; do
  echo "Checking $sql"
  "$PG_BIN/psql" -X -q -h "$sock" -p "$port" -U postgres -v ON_ERROR_STOP=1 -o /dev/null -f "$sql"
done
echo 'task_stats_counts_v2 contract passed.'
