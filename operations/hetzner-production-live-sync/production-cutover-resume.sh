#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${1:-}" != "--writers-stopped" || "${2:-}" != "--postgres-backup-only" ]]; then
  echo "usage: $0 --writers-stopped --postgres-backup-only" >&2
  exit 2
fi

SYNC_ROOT="/opt/sellton/live-sync"
SUPABASE_ROOT="/opt/sellton/supabase"
CUTOVER_MARKER="${SYNC_ROOT}/CUTOVER_COMPLETE"
SOURCE_READY_MARKER="${SYNC_ROOT}/STANDBY_SOURCE_READY"
STANDBY_MARKER="${SYNC_ROOT}/STANDBY_ENABLED"

if [[ -e "$CUTOVER_MARKER" || ! -s "$SOURCE_READY_MARKER" ]]; then
  echo "cutover markers do not match a resumable standby-initialization failure" >&2
  exit 1
fi

forward_subscription_enabled="$(docker exec supabase-db psql -X -v ON_ERROR_STOP=1 -U supabase_admin -d postgres -Atc "SELECT coalesce(bool_or(subenabled), false) FROM pg_subscription WHERE subname='sellton_cloud_to_hetzner'")"
if [[ "$forward_subscription_enabled" == "t" ]]; then
  echo "cloud-to-Hetzner PostgreSQL subscription is still enabled" >&2
  exit 1
fi
for service_name in sellton-mongodb-live-mirror.service sellton-storage-live-sync.timer; do
  if systemctl is-active --quiet "$service_name" || systemctl is-enabled --quiet "$service_name"; then
    echo "forward mirror is still active or enabled: $service_name" >&2
    exit 1
  fi
done

if [[ -s "$STANDBY_MARKER" ]]; then
  echo "reusing the initialized rollback standby"
  "${SYNC_ROOT}/production-standby-status.sh" --check
else
  date -u +%FT%TZ > "$SOURCE_READY_MARKER"
  chmod 600 "$SOURCE_READY_MARKER"
  "${SYNC_ROOT}/production-standby-enable.sh" --source-ready --postgres-backup-only
fi

echo "starting Hetzner Supabase"
docker compose -f "${SUPABASE_ROOT}/docker-compose.yml" --project-directory "$SUPABASE_ROOT" up -d rest analytics studio kong meta imgproxy storage supavisor vector auth functions realtime

set -a
# shellcheck disable=SC1090
source "${SUPABASE_ROOT}/.env"
set +a
for _ in $(seq 1 90); do
  if curl -fsS -H "apikey: $ANON_KEY" https://storagedb.sellton.ai/auth/v1/health >/dev/null 2>&1 && curl -fsS -H "apikey: $ANON_KEY" https://storagedb.sellton.ai/rest/v1/ >/dev/null 2>&1 && curl -fsS https://storagedb.sellton.ai/storage/v1/status >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
curl -fsS -H "apikey: $ANON_KEY" https://storagedb.sellton.ai/auth/v1/health >/dev/null
curl -fsS -H "apikey: $ANON_KEY" https://storagedb.sellton.ai/rest/v1/ >/dev/null
curl -fsS https://storagedb.sellton.ai/storage/v1/status >/dev/null

"${SYNC_ROOT}/backoffice-cutover-update.sh"
date -u +%FT%TZ > "$CUTOVER_MARKER"
chmod 600 "$CUTOVER_MARKER"
unset ANON_KEY SERVICE_ROLE_KEY

echo "DATABASE CUTOVER COMPLETE"
echo "Storage and MongoDB reverse standby are active. PostgreSQL is protected by thirty-minute backup checkpoints, not live cloud apply."
