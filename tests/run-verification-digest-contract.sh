#!/usr/bin/env bash
# KAN-309 V2 (migration 405): a disposable local Postgres only; never connects to any deployed environment.
# public.notifications is built from its own migrations (245, 244, 361, and 376's type CHECK), so the RPC is proven
# against the table both lines actually have.
set -euo pipefail
export LC_ALL="${LC_ALL:-C}"
cd "$(dirname "$0")/.."
PG_BIN="${PG_BIN:-$(dirname "$(command -v postgres || echo /opt/homebrew/opt/postgresql@15/bin/postgres)")}"
data="$(mktemp -d)"; sock="$(mktemp -d /tmp/pgs.XXXX)"; port="${PG_TEST_PORT:-55441}"
trap '"$PG_BIN/pg_ctl" -D "$data" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$data" "$sock"' EXIT
"$PG_BIN/initdb" -D "$data" -U postgres -A trust >/dev/null
"$PG_BIN/pg_ctl" -D "$data" -o "-p $port -k $sock -c listen_addresses=''" -l "$data/server.log" -w start >/dev/null || { cat "$data/server.log"; exit 1; }
for sql in tests/fixtures/verification-digest-bootstrap.sql \
           migrations/release_1.1.0/245_20260307_create_notifications_table.sql \
           migrations/release_1.1.0/244_20260307_add_notification_delivery_tracking.sql \
           migrations/release_1.3.0/361_notification-type-campaign-account-missing.sql \
           tests/fixtures/verification-digest-376-type-check.sql \
           migrations/next-release/405_bump-verification-digest.sql \
           migrations/next-release/405_bump-verification-digest.sql \
           tests/verification-digest-contract.sql; do
  echo "Checking $sql"
  "$PG_BIN/psql" -X -q -h "$sock" -p "$port" -U postgres -v ON_ERROR_STOP=1 -f "$sql"
done
echo 'bump_verification_digest contract (405) passed.'
