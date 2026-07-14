#!/usr/bin/env bash
set -Eeuo pipefail

umask 077

SYNC_ROOT="/opt/sellton/live-sync/storage"
SOURCE_API_ENV="/root/sellton-source.env"
SOURCE_PG_ENV="/root/sellton-source-pg.env"
MANIFEST="${SYNC_ROOT}/source-objects.jsonl"
STATUS="${SYNC_ROOT}/status.json"
TARGET_ROOT="/opt/sellton/supabase/volumes/storage"

mkdir -p "$SYNC_ROOT"
exec 9>"${SYNC_ROOT}/sync.lock"
if ! flock -n 9; then
  echo "storage synchronization is already running"
  exit 0
fi

set -a
# shellcheck disable=SC1090
source "$SOURCE_API_ENV"
# shellcheck disable=SC1090
source "$SOURCE_PG_ENV"
set +a

docker exec -i \
  -e PGHOST="$PGHOST" \
  -e PGPORT="$PGPORT" \
  -e PGDATABASE="$PGDATABASE" \
  -e PGUSER="$PGUSER" \
  -e PGPASSWORD="$PGPASSWORD" \
  -e PGSSLMODE="$PGSSLMODE" \
  supabase-db psql -X -At -v ON_ERROR_STOP=1 <<'SQL' > "${MANIFEST}.tmp"
SELECT json_build_object(
  'id', id,
  'bucket_id', bucket_id,
  'name', name,
  'version', version,
  'size', coalesce((metadata->>'size')::bigint, 0),
  'mimetype', coalesce(metadata->>'mimetype', 'application/octet-stream'),
  'cache_control', coalesce(metadata->>'cacheControl', 'no-cache'),
  'etag', metadata->>'eTag'
)::text
FROM storage.objects
ORDER BY bucket_id, name;
SQL
mv "${MANIFEST}.tmp" "$MANIFEST"

export STORAGE_SYNC_MANIFEST="$MANIFEST"
export STORAGE_SYNC_TARGET_ROOT="$TARGET_ROOT"
export STORAGE_SYNC_STATUS="$STATUS"
export STORAGE_SYNC_CONCURRENCY="${STORAGE_SYNC_CONCURRENCY:-4}"

node "${SYNC_ROOT}/storage-object-sync.js"

