#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${1:-}" != "--writers-stopped" ]]; then
  echo "usage: $0 --writers-stopped" >&2
  echo "Stop Hetzner Gmail, Modal, Vercel writes, backoffice, crawler, and onboarding first." >&2
  exit 2
fi

SYNC_ROOT="/opt/sellton/live-sync"
STANDBY_MARKER="${SYNC_ROOT}/STANDBY_ENABLED"
DISABLED_MARKER="${SYNC_ROOT}/STANDBY_DISABLED"
POSTGRES_MODE_MARKER="${SYNC_ROOT}/POSTGRES_STANDBY_MODE"

if [[ ! -s "$STANDBY_MARKER" ]]; then
  echo "standby enabled marker is missing: $STANDBY_MARKER" >&2
  exit 1
fi
if systemctl is-active --quiet sellton-gmail-api-prod.service; then
  echo "Hetzner Gmail API must be stopped before disabling standby" >&2
  exit 1
fi

echo "running final Storage standby pass"
systemctl stop sellton-storage-standby.timer
"${SYNC_ROOT}/storage-standby/storage-standby-sync-run.sh" sync
systemctl start sellton-storage-standby.timer
"${SYNC_ROOT}/production-standby-status.sh" --check

postgres_mode="$(cat "$POSTGRES_MODE_MARKER" 2>/dev/null || echo live)"
if [[ "$postgres_mode" == "backup-only" ]]; then
  echo "creating final PostgreSQL backup checkpoint; hosted PostgreSQL is not synchronized"
  "${SYNC_ROOT}/postgres-standby/postgres-standby-backup.sh"
else
  echo "synchronizing PostgreSQL sequences to cloud"
  "${SYNC_ROOT}/postgres/postgres-sequence-sync.sh" hetzner-to-cloud
fi

echo "stopping Hetzner-to-cloud standby services"
systemctl disable --now sellton-mongodb-standby.service
systemctl disable --now sellton-storage-standby.timer
systemctl stop sellton-storage-standby.service || true
systemctl disable --now sellton-postgres-standby.service
systemctl disable --now sellton-postgres-backup-standby.timer

date -u +%FT%TZ > "$DISABLED_MARKER"
chmod 600 "$DISABLED_MARKER"
if [[ "$postgres_mode" == "backup-only" ]]; then
  echo "STANDBY DISABLED; POSTGRESQL ROLLBACK REQUIRES MANUAL CHECKPOINT RESTORE"
else
  echo "HETZNER-TO-CLOUD STANDBY DISABLED AT ZERO LAG"
fi
