#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${1:-}" != "--writers-stopped" ]]; then
  echo "usage: $0 --writers-stopped" >&2
  echo "Stop cloud Gmail API, Modal, Vercel writes, crawler, and onboarding writers first." >&2
  exit 2
fi

SYNC_ROOT="/opt/sellton/live-sync"
SUPABASE_ROOT="/opt/sellton/supabase"
SUBSCRIPTION="sellton_cloud_to_hetzner"
CUTOVER_MARKER="${SYNC_ROOT}/CUTOVER_COMPLETE"
SOURCE_READY_MARKER="${SYNC_ROOT}/STANDBY_SOURCE_READY"
STANDBY_MARKER="${SYNC_ROOT}/STANDBY_ENABLED"

if [[ -e "$CUTOVER_MARKER" ]]; then
  echo "cutover was already completed: $CUTOVER_MARKER" >&2
  exit 1
fi
if [[ -e "$SOURCE_READY_MARKER" || -e "$STANDBY_MARKER" ]]; then
  echo "standby marker already exists; inspect before repeating cutover" >&2
  exit 1
fi

echo "stopping the Hetzner backoffice writer"
docker stop backoffice-backoffice-1 >/dev/null 2>&1 || true

echo "running preflight before final Storage pass"
"${SYNC_ROOT}/production-cutover-preflight.sh"
systemctl start sellton-storage-live-sync.service

echo "running final zero-lag preflight"
"${SYNC_ROOT}/production-cutover-preflight.sh"

echo "stopping forward mirrors"
systemctl disable --now sellton-storage-live-sync.timer
docker exec supabase-db psql -X -v ON_ERROR_STOP=1 -U supabase_admin -d postgres -c "ALTER SUBSCRIPTION $SUBSCRIPTION DISABLE"
"${SYNC_ROOT}/postgres/postgres-sequence-sync.sh" cloud-to-hetzner
systemctl disable --now sellton-mongodb-live-mirror.service

if systemctl is-active --quiet sellton-mongodb-live-mirror.service; then
  echo "MongoDB mirror did not stop" >&2
  exit 1
fi

echo "initializing Hetzner-to-cloud standby before the first Hetzner write"
date -u +%FT%TZ > "$SOURCE_READY_MARKER"
chmod 600 "$SOURCE_READY_MARKER"
"${SYNC_ROOT}/production-standby-enable.sh" --source-ready

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

echo "updating Hetzner backoffice to the Hetzner Supabase endpoint"
"${SYNC_ROOT}/backoffice-cutover-update.sh"

date -u +%FT%TZ > "$CUTOVER_MARKER"
chmod 0600 "$CUTOVER_MARKER"
unset ANON_KEY SERVICE_ROLE_KEY

echo "DATABASE CUTOVER COMPLETE"
echo "Hetzner-to-cloud standby is active. Update and redeploy Vercel and Modal, then run ${SYNC_ROOT}/production-activate.sh."
