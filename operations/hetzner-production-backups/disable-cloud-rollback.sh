#!/usr/bin/env bash
set -Eeuo pipefail

umask 077

DECOMMISSION_MODE=""
case "${1:-} ${2:-} ${3:-}" in
  "--online-backups-downloaded  ")
    DECOMMISSION_MODE="online"
    ;;
  "--writers-stopped --backups-downloaded ")
    DECOMMISSION_MODE="writer-stopped"
    ;;
  *)
    echo "usage: $0 --online-backups-downloaded" >&2
    echo "   or: $0 --writers-stopped --backups-downloaded" >&2
    echo "Run only after the corresponding fresh bundles pass local checksum verification." >&2
    exit 2
    ;;
esac

SYNC_ROOT="${SYNC_ROOT:-/opt/sellton/live-sync}"
BACKUP_ROOT="${BACKUP_ROOT:-/opt/sellton/backups/downloadable}"
DISABLED_MARKER="${SYNC_ROOT}/CLOUD_ROLLBACK_DISABLED"
MAX_BACKUP_AGE_SECONDS="${MAX_BACKUP_AGE_SECONDS:-3600}"

verify_final_bundle() {
  local bundle_name="$1"
  local latest_link="${BACKUP_ROOT}/${bundle_name}-production-latest.tar.gz"
  local archive_path
  local archive_age_seconds

  archive_path="$(readlink -f "$latest_link")"
  if [[ "$archive_path" != "${BACKUP_ROOT}/${bundle_name}-production-"*.tar.gz || ! -s "$archive_path" ]]; then
    echo "missing latest ${bundle_name} production bundle" >&2
    exit 1
  fi
  if [[ ! -s "${archive_path}.sha256" ]]; then
    echo "missing checksum for ${archive_path}" >&2
    exit 1
  fi

  (
    cd "$BACKUP_ROOT"
    sha256sum --check "$(basename "${archive_path}.sha256")" >/dev/null
  )

  if [[ "$DECOMMISSION_MODE" == "online" ]]; then
    if ! tar -xOzf "$archive_path" ./MANIFEST.txt | grep -qx 'snapshot_mode=online-point-in-time'; then
      echo "${bundle_name} bundle is not an online point-in-time snapshot: ${archive_path}" >&2
      exit 1
    fi
  elif ! tar -xOzf "$archive_path" ./MANIFEST.txt | grep -qx 'writers_stopped=true'; then
    echo "${bundle_name} bundle is not marked writers_stopped=true: ${archive_path}" >&2
    exit 1
  fi

  archive_age_seconds="$(( $(date +%s) - $(stat -c %Y "$archive_path") ))"
  if [[ "$archive_age_seconds" -lt 0 || "$archive_age_seconds" -gt "$MAX_BACKUP_AGE_SECONDS" ]]; then
    echo "${bundle_name} bundle is too old for decommission: ${archive_age_seconds}s" >&2
    exit 1
  fi

  echo "verified final ${bundle_name} bundle: ${archive_path}"
}

verify_final_bundle supabase
verify_final_bundle mongodb

echo "running final Supabase Storage cloud synchronization"
systemctl stop sellton-storage-standby.timer
"${SYNC_ROOT}/storage-standby/storage-standby-sync-run.sh" sync
systemctl start sellton-storage-standby.timer

echo "verifying all rollback targets before shutdown"
"${SYNC_ROOT}/production-standby-status.sh" --check

echo "stopping cloud rollback mirrors"
systemctl disable --now sellton-mongodb-standby.service
systemctl disable --now sellton-storage-standby.timer
systemctl stop sellton-storage-standby.service || true
systemctl disable --now sellton-postgres-standby.service

echo "preserving the independent weekly PostgreSQL checkpoint"
systemctl enable --now sellton-postgres-backup-standby.timer

if systemctl is-active --quiet sellton-mongodb-standby.service; then
  echo "MongoDB cloud rollback service is still active" >&2
  exit 1
fi
if systemctl is-active --quiet sellton-storage-standby.timer; then
  echo "Storage cloud rollback timer is still active" >&2
  exit 1
fi
if ! systemctl is-active --quiet sellton-postgres-backup-standby.timer; then
  echo "PostgreSQL backup timer is not active" >&2
  exit 1
fi

date -u +%FT%TZ > "$DISABLED_MARKER"
chmod 600 "$DISABLED_MARKER"

echo "CLOUD ROLLBACK DISABLED (${DECOMMISSION_MODE}); WEEKLY HETZNER POSTGRESQL BACKUP REMAINS ACTIVE"
