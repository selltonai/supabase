#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_ENV="/root/sellton-source-pg.env"
SUBSCRIPTION="sellton_cloud_to_hetzner"

set -a
# shellcheck disable=SC1090
source "$SOURCE_ENV"
set +a

source_psql() {
  docker exec -i \
    -e PGHOST="$PGHOST" \
    -e PGPORT="$PGPORT" \
    -e PGDATABASE="$PGDATABASE" \
    -e PGUSER="$PGUSER" \
    -e PGPASSWORD="$PGPASSWORD" \
    -e PGSSLMODE="$PGSSLMODE" \
    supabase-db psql -X -v ON_ERROR_STOP=1 "$@"
}

target_psql() {
  docker exec -i supabase-db psql -X -v ON_ERROR_STOP=1 -U supabase_admin -d postgres "$@"
}

echo "postgres_subscription"
target_psql -P pager=off -c "
SELECT
  subname,
  pid,
  received_lsn,
  latest_end_lsn,
  last_msg_receipt_time,
  latest_end_time
FROM pg_stat_subscription
WHERE subname = '$SUBSCRIPTION';
"

echo "postgres_table_states"
target_psql -P pager=off -c "
SELECT srsubstate AS state, count(*) AS table_count
FROM pg_subscription_rel
WHERE srsubid = (SELECT oid FROM pg_subscription WHERE subname = '$SUBSCRIPTION')
GROUP BY srsubstate
ORDER BY srsubstate;
"

echo "postgres_non_ready_tables"
target_psql -P pager=off -c "
SELECT n.nspname AS schema_name, c.relname AS table_name, sr.srsubstate AS state
FROM pg_subscription_rel sr
JOIN pg_class c ON c.oid = sr.srrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE sr.srsubid = (SELECT oid FROM pg_subscription WHERE subname = '$SUBSCRIPTION')
  AND sr.srsubstate <> 'r'
ORDER BY n.nspname, c.relname;
"

echo "postgres_copy_progress"
target_psql -P pager=off -c "
SELECT n.nspname AS schema_name, c.relname AS table_name, p.bytes_processed, p.tuples_processed
FROM pg_stat_progress_copy p
JOIN pg_class c ON c.oid = p.relid
JOIN pg_namespace n ON n.oid = c.relnamespace
ORDER BY n.nspname, c.relname;
"

echo "postgres_subscription_errors"
target_psql -P pager=off -c "
SELECT apply_error_count, sync_error_count, stats_reset
FROM pg_stat_subscription_stats
WHERE subname = '$SUBSCRIPTION';
"

echo "postgres_source_slot"
source_psql -P pager=off -c "
SELECT
  slot_name,
  active,
  confirmed_flush_lsn,
  pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn)) AS retained_lag
FROM pg_replication_slots
WHERE slot_name = '$SUBSCRIPTION';
"

echo "postgres_critical_counts_source"
source_psql -Atc "
SELECT
  (SELECT count(*) FROM public.organization),
  (SELECT count(*) FROM public.campaigns),
  (SELECT count(*) FROM public.companies),
  (SELECT count(*) FROM public.contacts),
  (SELECT count(*) FROM public.tasks),
  (SELECT count(*) FROM storage.objects);
"

echo "postgres_critical_counts_target"
target_psql -Atc "
SELECT
  (SELECT count(*) FROM public.organization),
  (SELECT count(*) FROM public.campaigns),
  (SELECT count(*) FROM public.companies),
  (SELECT count(*) FROM public.contacts),
  (SELECT count(*) FROM public.tasks),
  (SELECT count(*) FROM storage.objects);
"

echo "hetzner_gmail_api"
systemctl is-active sellton-gmail-api-prod.service || true
