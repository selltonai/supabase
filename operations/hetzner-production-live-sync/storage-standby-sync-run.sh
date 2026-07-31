#!/usr/bin/env bash
set -Eeuo pipefail

umask 077

MODE="${1:-sync}"
SYNC_ROOT="/opt/sellton/live-sync/storage-standby"
SOURCE_API_ENV="/root/sellton-source.env"
MANIFEST="${SYNC_ROOT}/hetzner-objects.jsonl"
BUCKET_MANIFEST="${SYNC_ROOT}/hetzner-buckets.jsonl"
STATUS="${SYNC_ROOT}/status.json"
STATE="${SYNC_ROOT}/state.json"
SOURCE_ROOT="/opt/sellton/supabase/volumes/storage"

if [[ "$MODE" != "seed" && "$MODE" != "sync" ]]; then
  echo "usage: $0 seed|sync" >&2
  exit 2
fi

install -d -m 700 "$SYNC_ROOT"
exec 9>"${SYNC_ROOT}/sync.lock"
if ! flock -n 9; then
  echo "Storage standby synchronization is already running"
  exit 0
fi

set -a
# shellcheck disable=SC1090
source "$SOURCE_API_ENV"
set +a

docker exec -i supabase-db psql -X -At -v ON_ERROR_STOP=1 -U supabase_admin -d postgres <<'SQL' > "${MANIFEST}.tmp"
SELECT json_build_object(
  'id', id,
  'bucket_id', bucket_id,
  'name', name,
  'version', version,
  'size', coalesce((metadata->>'size')::bigint, 0),
  'mimetype', coalesce(metadata->>'mimetype', 'application/octet-stream'),
  'cache_control', coalesce(metadata->>'cacheControl', 'no-cache'),
  'etag', metadata->>'eTag',
  'user_metadata', coalesce(user_metadata, '{}'::jsonb)
)::text
FROM storage.objects
ORDER BY bucket_id, name;
SQL
mv "${MANIFEST}.tmp" "$MANIFEST"

docker exec -i supabase-db psql -X -At -v ON_ERROR_STOP=1 -U supabase_admin -d postgres <<'SQL' > "${BUCKET_MANIFEST}.tmp"
SELECT json_build_object(
  'id', id,
  'public', public,
  'file_size_limit', file_size_limit,
  'allowed_mime_types', allowed_mime_types
)::text
FROM storage.buckets
ORDER BY id;
SQL
mv "${BUCKET_MANIFEST}.tmp" "$BUCKET_MANIFEST"

export STORAGE_STANDBY_MANIFEST="$MANIFEST"
export STORAGE_STANDBY_BUCKET_MANIFEST="$BUCKET_MANIFEST"
export STORAGE_STANDBY_STATE="$STATE"
export STORAGE_STANDBY_STATUS="$STATUS"
export STORAGE_STANDBY_SOURCE_ROOT="$SOURCE_ROOT"
export STORAGE_STANDBY_MODE="$MODE"
export STORAGE_STANDBY_CONCURRENCY="${STORAGE_STANDBY_CONCURRENCY:-2}"

node "${SYNC_ROOT}/storage-standby-object-sync.js"
