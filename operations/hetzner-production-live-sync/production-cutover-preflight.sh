#!/usr/bin/env bash
set -Eeuo pipefail

SUBSCRIPTION="sellton_cloud_to_hetzner"
SOURCE_PG_ENV="/root/sellton-source-pg.env"
SOURCE_MONGO_ENV="/root/sellton-source-mongo.env"
TARGET_MONGO_URI_FILE="/opt/sellton/mongodb-prod/root-uri.local.txt"
STORAGE_STATUS="/opt/sellton/live-sync/storage/status.json"
MONGO_STATE="/var/lib/sellton-mongodb-live-mirror/state.json"

set -a
# shellcheck disable=SC1090
source "$SOURCE_PG_ENV"
set +a

source_psql() {
  docker exec -i -e PGHOST="$PGHOST" -e PGPORT="$PGPORT" -e PGDATABASE="$PGDATABASE" -e PGUSER="$PGUSER" -e PGPASSWORD="$PGPASSWORD" -e PGSSLMODE="$PGSSLMODE" supabase-db psql -X -v ON_ERROR_STOP=1 "$@"
}

target_psql() {
  docker exec -i supabase-db psql -X -v ON_ERROR_STOP=1 -U supabase_admin -d postgres "$@"
}

echo "checking PostgreSQL logical replication"
non_ready_count="$(target_psql -Atc "SELECT count(*) FROM pg_subscription_rel WHERE srsubid=(SELECT oid FROM pg_subscription WHERE subname='$SUBSCRIPTION') AND srsubstate<>'r'")"
subscription_errors="$(target_psql -Atc "SELECT apply_error_count + sync_error_count FROM pg_stat_subscription_stats WHERE subname='$SUBSCRIPTION'")"
postgres_lag_bytes="$(source_psql -Atc "SELECT coalesce(pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn), -1)::bigint FROM pg_replication_slots WHERE slot_name='$SUBSCRIPTION'")"
if [[ "$non_ready_count" != "0" || "$subscription_errors" != "0" || -z "$postgres_lag_bytes" || "$postgres_lag_bytes" == "-1" || "$postgres_lag_bytes" -gt 1048576 ]]; then
  echo "PostgreSQL mirror is not ready: non_ready=$non_ready_count errors=$subscription_errors lag_bytes=${postgres_lag_bytes:-missing}" >&2
  exit 1
fi

source_counts="$(source_psql -Atc "SELECT (SELECT count(*) FROM public.organization),(SELECT count(*) FROM public.campaigns),(SELECT count(*) FROM public.companies),(SELECT count(*) FROM public.contacts),(SELECT count(*) FROM public.tasks),(SELECT count(*) FROM storage.objects)")"
target_counts="$(target_psql -Atc "SELECT (SELECT count(*) FROM public.organization),(SELECT count(*) FROM public.campaigns),(SELECT count(*) FROM public.companies),(SELECT count(*) FROM public.contacts),(SELECT count(*) FROM public.tasks),(SELECT count(*) FROM storage.objects)")"
if [[ "$source_counts" != "$target_counts" ]]; then
  echo "PostgreSQL critical counts differ: source=$source_counts target=$target_counts" >&2
  exit 1
fi

echo "checking Supabase Storage mirror"
storage_values="$(STATUS_FILE="$STORAGE_STATUS" node -e 'const status=require(process.env.STATUS_FILE); process.stdout.write(`${status.manifest_objects}|${status.synchronized_objects}|${status.failures?.length || 0}`)')"
source_storage_count="${source_counts##*|}"
if [[ "$storage_values" != "$source_storage_count|$source_storage_count|0" ]]; then
  echo "Storage mirror is not ready: source=$source_storage_count status=$storage_values" >&2
  exit 1
fi

echo "checking MongoDB change-stream mirror"
mongo_values="$(STATE_FILE="$MONGO_STATE" node -e 'const {BSON}=require("/opt/sellton/gmail-api-prod/node_modules/mongodb"); const fs=require("fs"); const state=BSON.EJSON.parse(fs.readFileSync(process.env.STATE_FILE,"utf8"),{relaxed:true}); process.stdout.write(`${state.phase}|${state.completedCollections.length}|${state.totalCollections}|${state.lagSeconds}|${state.lastError ? 1 : 0}`)')"
IFS='|' read -r mongo_phase mongo_completed mongo_total mongo_lag mongo_error <<< "$mongo_values"
if [[ "$mongo_phase" != "live" || "$mongo_completed" != "$mongo_total" || "$mongo_total" -lt 14 || "$mongo_lag" -gt 5 || "$mongo_error" != "0" ]]; then
  echo "MongoDB mirror is not ready: phase=$mongo_phase collections=$mongo_completed/$mongo_total lag=$mongo_lag error=$mongo_error" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$SOURCE_MONGO_ENV"
set +a
MONGO_MIRROR_TARGET_URI="$(cat "$TARGET_MONGO_URI_FILE")" MONGO_MIRROR_DATABASE=production node /opt/sellton/gmail-api-prod/scripts/mongodb-live-mirror.js --verify

if systemctl is-active --quiet sellton-gmail-api-prod.service; then
  echo "Hetzner Gmail API must remain stopped until external production endpoints are updated" >&2
  exit 1
fi

unset PGPASSWORD HOSTED_MONGODB_URI MONGO_MIRROR_SOURCE_URI
echo "CUTOVER PREFLIGHT PASSED"
echo "PostgreSQL lag: $postgres_lag_bytes bytes"
echo "PostgreSQL critical counts: $source_counts"
echo "Storage objects: $source_storage_count"
echo "MongoDB collections: $mongo_total; lag: $mongo_lag seconds"
