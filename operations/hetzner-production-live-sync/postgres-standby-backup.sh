#!/usr/bin/env bash
set -Eeuo pipefail

umask 077

BACKUP_ROOT="/opt/sellton/backups/post-cutover-postgres"
STATUS_FILE="/opt/sellton/live-sync/postgres-standby/backup-status.env"
timestamp="$(date -u +%Y%m%d-%H%M%S)"
backup_path="${BACKUP_ROOT}/postgres-${timestamp}.dump"
temporary_path="${backup_path}.tmp"

install -d -m 700 "$BACKUP_ROOT"
install -d -m 700 "$(dirname "$STATUS_FILE")"

if [[ -r "$STATUS_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$STATUS_FILE"
  backup_age_seconds="$(( $(date +%s) - ${BACKUP_EPOCH:-0} ))"
  if [[ "$backup_age_seconds" -ge 0 && "$backup_age_seconds" -le 600 && -s "${BACKUP_PATH:-}" && -s "${BACKUP_PATH:-}.sha256" ]]; then
    sha256sum --check "${BACKUP_PATH}.sha256" >/dev/null
    docker exec -i supabase-db pg_restore --list < "$BACKUP_PATH" >/dev/null
    echo "Reusing recent verified PostgreSQL checkpoint: $BACKUP_PATH"
    exit 0
  fi
fi

cleanup() {
  rm -f "$temporary_path"
}
trap cleanup EXIT

docker exec supabase-db pg_dump \
  -U supabase_admin \
  -d postgres \
  --format=custom \
  --no-owner \
  --no-privileges \
  --lock-wait-timeout=30s > "$temporary_path"

docker exec -i supabase-db pg_restore --list < "$temporary_path" >/dev/null
mv "$temporary_path" "$backup_path"
sha256sum "$backup_path" > "${backup_path}.sha256"
ln -sfn "$(basename "$backup_path")" "${BACKUP_ROOT}/latest.dump"

cat > "${STATUS_FILE}.tmp" <<EOF
BACKUP_COMPLETED_AT=$(date -u +%FT%TZ)
BACKUP_EPOCH=$(date +%s)
BACKUP_PATH=$backup_path
BACKUP_BYTES=$(stat -c %s "$backup_path")
EOF
mv "${STATUS_FILE}.tmp" "$STATUS_FILE"
chmod 600 "$STATUS_FILE"

echo "PostgreSQL backup checkpoint completed: $backup_path"
