#!/usr/bin/env bash
set -Eeuo pipefail

umask 077

SUPABASE_ROOT="${SUPABASE_ROOT:-/opt/sellton/supabase}"
SYNC_ROOT="${SYNC_ROOT:-/opt/sellton/live-sync}"
DECOMMISSION_MARKER="${SYNC_ROOT}/CLOUD_ROLLBACK_DISABLED"
FORWARD_RETIRED_MARKER="${SYNC_ROOT}/FORWARD_REPLICATION_RETIRED"

require_active_unit() {
  local unit_name="$1"
  if ! systemctl is-active --quiet "$unit_name"; then
    echo "required unit is not active: $unit_name" >&2
    exit 1
  fi
  echo "${unit_name}=active"
}

require_inactive_unit() {
  local unit_name="$1"
  if systemctl is-active --quiet "$unit_name"; then
    echo "cloud rollback unit is still active: $unit_name" >&2
    exit 1
  fi
  if systemctl is-enabled --quiet "$unit_name"; then
    echo "cloud rollback unit is still enabled: $unit_name" >&2
    exit 1
  fi
  echo "${unit_name}=inactive-disabled"
}

require_healthy_container() {
  local container_name="$1"
  local running
  local health

  running="$(docker inspect --format '{{.State.Running}}' "$container_name" 2>/dev/null || true)"
  health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$container_name" 2>/dev/null || true)"
  if [[ "$running" != "true" || "$health" == "unhealthy" ]]; then
    echo "container is not healthy: ${container_name} running=${running} health=${health}" >&2
    exit 1
  fi
  echo "${container_name}=running-${health}"
}

if [[ ! -s "$DECOMMISSION_MARKER" ]]; then
  echo "cloud rollback decommission marker is missing" >&2
  exit 1
fi
if [[ ! -s "$FORWARD_RETIRED_MARKER" ]]; then
  echo "forward PostgreSQL retirement marker is missing" >&2
  exit 1
fi

require_active_unit sellton-gmail-api-prod.service
require_active_unit sellton-postgres-backup-standby.timer
require_inactive_unit sellton-mongodb-standby.service
require_inactive_unit sellton-storage-standby.timer
require_inactive_unit sellton-postgres-standby.service

for container_name in \
  supabase-db \
  supabase-kong \
  supabase-auth \
  supabase-storage \
  supabase-rest \
  sellton-mongodb-prod \
  sellton-mongodb-prod-2 \
  sellton-mongodb-prod-3; do
  require_healthy_container "$container_name"
done

set -a
# shellcheck disable=SC1091
source "${SUPABASE_ROOT}/.env"
set +a

curl -fsS \
  -H "apikey: ${ANON_KEY}" \
  https://storagedb.sellton.ai/auth/v1/health >/dev/null
curl -fsS https://emailapi.sellton.ai/ve/health/health >/dev/null

echo "supabase_public_health=healthy"
echo "gmail_api_public_health=healthy"
echo "postgres_forward_replication=retired"
echo "cloud_rollback=disabled"
echo "HETZNER-ONLY PRODUCTION CHECK PASSED"
