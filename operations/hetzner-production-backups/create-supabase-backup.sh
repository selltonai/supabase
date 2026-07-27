#!/usr/bin/env bash
set -Eeuo pipefail

umask 077

SUPABASE_ROOT="${SUPABASE_ROOT:-/opt/sellton/supabase}"
BACKUP_ROOT="${BACKUP_ROOT:-/opt/sellton/backups/downloadable}"
DB_CONTAINER="${DB_CONTAINER:-supabase-db}"
WRITERS_STOPPED=false
SNAPSHOT_MODE="online-point-in-time"

if [[ "${1:-}" == "--writers-stopped" ]]; then
  WRITERS_STOPPED=true
  SNAPSHOT_MODE="writer-stopped"
elif [[ -n "${1:-}" ]]; then
  echo "usage: $0 [--writers-stopped]" >&2
  exit 2
fi

required_commands=(docker find flock install rsync sha256sum tar)
for command_name in "${required_commands[@]}"; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "missing required command: $command_name" >&2
    exit 1
  fi
done

if [[ ! -f "${SUPABASE_ROOT}/docker-compose.yml" ]]; then
  echo "missing Supabase compose file: ${SUPABASE_ROOT}/docker-compose.yml" >&2
  exit 1
fi
if [[ ! -d "${SUPABASE_ROOT}/volumes/storage" ]]; then
  echo "missing Supabase Storage data: ${SUPABASE_ROOT}/volumes/storage" >&2
  exit 1
fi
if [[ "$(docker inspect --format '{{.State.Running}}' "$DB_CONTAINER" 2>/dev/null)" != "true" ]]; then
  echo "Supabase database container is not running: $DB_CONTAINER" >&2
  exit 1
fi

install -d -m 700 "$BACKUP_ROOT"
exec 9>"${BACKUP_ROOT}/.supabase-backup.lock"
if ! flock -n 9; then
  echo "another Supabase backup is already running" >&2
  exit 1
fi

timestamp="$(date -u +%Y%m%d-%H%M%S)"
archive_name="supabase-production-${timestamp}.tar.gz"
archive_path="${BACKUP_ROOT}/${archive_name}"
temporary_archive="${archive_path}.tmp"
staging_directory="${BACKUP_ROOT}/.${archive_name}.staging"

cleanup() {
  rm -rf "$staging_directory"
  rm -f "$temporary_archive"
}
trap cleanup EXIT

install -d -m 700 "$staging_directory"

echo "creating PostgreSQL database dump"
database_dump_started_at="$(date -u +%FT%TZ)"
docker exec "$DB_CONTAINER" pg_dump \
  -U supabase_admin \
  -d postgres \
  --format=custom \
  --no-owner \
  --no-privileges \
  --serializable-deferrable \
  --lock-wait-timeout=30s > "${staging_directory}/database.dump"
docker exec -i "$DB_CONTAINER" pg_restore --list < "${staging_directory}/database.dump" >/dev/null
database_dump_completed_at="$(date -u +%FT%TZ)"

echo "exporting PostgreSQL roles without passwords"
docker exec "$DB_CONTAINER" pg_dumpall \
  -U supabase_admin \
  --globals-only \
  --no-role-passwords > "${staging_directory}/globals.sql"

echo "capturing a stable online Supabase Storage snapshot"
storage_capture_started_at="$(date -u +%FT%TZ)"
storage_snapshot_directory="${staging_directory}/storage-snapshot"
storage_changes_file="${staging_directory}/.storage-rsync-changes"
install -d -m 700 "$storage_snapshot_directory"
storage_sync_passes=0
storage_snapshot_stable=false
for storage_sync_passes in 1 2 3 4 5; do
  rsync \
    --archive \
    --delete \
    --itemize-changes \
    "${SUPABASE_ROOT}/volumes/storage/" \
    "${storage_snapshot_directory}/" > "$storage_changes_file"
  storage_change_count="$(wc -l < "$storage_changes_file")"
  if [[ "$storage_sync_passes" -gt 1 && "$storage_change_count" -eq 0 ]]; then
    storage_snapshot_stable=true
    break
  fi
done
rm -f "$storage_changes_file"
if [[ "$storage_snapshot_stable" != "true" ]]; then
  echo "Supabase Storage did not reach a stable rsync pass after five attempts" >&2
  exit 1
fi

(
  cd "$storage_snapshot_directory"
  find . -type f -print0 | sort -z | xargs -0 -r sha256sum
) > "${staging_directory}/storage-files.sha256"
tar -C "$storage_snapshot_directory" -cf "${staging_directory}/storage.tar" .
tar -tf "${staging_directory}/storage.tar" >/dev/null
rm -rf "$storage_snapshot_directory"
storage_capture_completed_at="$(date -u +%FT%TZ)"

echo "archiving non-secret Supabase stack configuration"
stack_paths=(docker-compose.yml)
optional_stack_paths=(
  .env.example
  volumes/api
  volumes/db/init
  volumes/functions
  volumes/logs
  volumes/pooler
  volumes/proxy
  volumes/snippets
)
for optional_path in "${optional_stack_paths[@]}"; do
  if [[ -e "${SUPABASE_ROOT}/${optional_path}" ]]; then
    stack_paths+=("$optional_path")
  fi
done
tar -C "$SUPABASE_ROOT" -cf "${staging_directory}/stack-config.tar" "${stack_paths[@]}"
tar -tf "${staging_directory}/stack-config.tar" >/dev/null

docker compose -f "${SUPABASE_ROOT}/docker-compose.yml" --project-directory "$SUPABASE_ROOT" config --images \
  | sort -u > "${staging_directory}/docker-images.txt"

storage_file_count="$(wc -l < "${staging_directory}/storage-files.sha256")"
storage_bytes="$(stat -c %s "${staging_directory}/storage.tar")"
database_bytes="$(stat -c %s "${staging_directory}/database.dump")"

cat > "${staging_directory}/MANIFEST.txt" <<EOF
backup_type=supabase-production
created_at=$(date -u +%FT%TZ)
source_host=$(hostname -f 2>/dev/null || hostname)
snapshot_mode=${SNAPSHOT_MODE}
database=postgres
database_container=${DB_CONTAINER}
database_bytes=${database_bytes}
database_consistency=mvcc-point-in-time
database_dump_started_at=${database_dump_started_at}
database_dump_completed_at=${database_dump_completed_at}
storage_file_count=${storage_file_count}
storage_bytes=${storage_bytes}
storage_consistency=stable-rsync-copy
storage_sync_passes=${storage_sync_passes}
storage_capture_started_at=${storage_capture_started_at}
storage_capture_completed_at=${storage_capture_completed_at}
writers_stopped=${WRITERS_STOPPED}
contains_active_env=false
contains_database_role_passwords=false
EOF

(
  cd "$staging_directory"
  sha256sum database.dump globals.sql storage.tar storage-files.sha256 stack-config.tar docker-images.txt MANIFEST.txt > CONTENTS.sha256
  sha256sum --check CONTENTS.sha256 >/dev/null
)

echo "creating downloadable Supabase bundle"
tar -C "$staging_directory" -czf "$temporary_archive" .
tar -tzf "$temporary_archive" >/dev/null
mv "$temporary_archive" "$archive_path"
(
  cd "$BACKUP_ROOT"
  sha256sum "$archive_name" > "${archive_name}.sha256"
  sha256sum --check "${archive_name}.sha256" >/dev/null
)

ln -sfn "$archive_name" "${BACKUP_ROOT}/supabase-production-latest.tar.gz"
ln -sfn "${archive_name}.sha256" "${BACKUP_ROOT}/supabase-production-latest.tar.gz.sha256"

mapfile -t old_archives < <(
  find "$BACKUP_ROOT" -maxdepth 1 -type f -name 'supabase-production-*.tar.gz' \
    -printf '%T@ %p\n' | sort -nr | awk 'NR > 2 {sub(/^[^ ]+ /, ""); print}'
)
for old_archive in "${old_archives[@]}"; do
  rm -f "$old_archive" "${old_archive}.sha256"
done

echo "backup-created: $archive_path"
