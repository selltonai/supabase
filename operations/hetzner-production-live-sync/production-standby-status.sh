#!/usr/bin/env bash
set -Eeuo pipefail

MODE="${1:-status}"
SYNC_ROOT="/opt/sellton/live-sync"
MONGO_STATE="/var/lib/sellton-mongodb-standby/state.json"
RETIRED_MARKER="${SYNC_ROOT}/FORWARD_REPLICATION_RETIRED"
POSTGRES_MODE_MARKER="${SYNC_ROOT}/POSTGRES_STANDBY_MODE"
POSTGRES_BACKUP_STATUS="${SYNC_ROOT}/postgres-standby/backup-status.env"

check_argument=()
if [[ "$MODE" == "--check" ]]; then
  check_argument=(--check)
elif [[ "$MODE" != "status" ]]; then
  echo "usage: $0 [--check]" >&2
  exit 2
fi

echo "=== PostgreSQL: Hetzner -> cloud ==="
postgres_mode="$(cat "$POSTGRES_MODE_MARKER" 2>/dev/null || echo live)"
if [[ "$postgres_mode" == "backup-only" ]]; then
  postgres_backup_timer="$(systemctl is-active sellton-postgres-backup-standby.timer 2>/dev/null || true)"
  postgres_backup_enabled="$(systemctl is-enabled sellton-postgres-backup-standby.timer 2>/dev/null || true)"
  backup_epoch=0
  backup_path=""
  backup_bytes=0
  if [[ -r "$POSTGRES_BACKUP_STATUS" ]]; then
    # shellcheck disable=SC1090
    source "$POSTGRES_BACKUP_STATUS"
    backup_epoch="${BACKUP_EPOCH:-0}"
    backup_path="${BACKUP_PATH:-}"
    backup_bytes="${BACKUP_BYTES:-0}"
  fi
  backup_age_seconds="$(( $(date +%s) - backup_epoch ))"
  echo "postgres_standby_mode=backup-only"
  echo "postgres_backup_timer=$postgres_backup_timer"
  echo "postgres_backup_enabled=$postgres_backup_enabled"
  echo "postgres_backup_path=${backup_path:-missing}"
  echo "postgres_backup_bytes=$backup_bytes"
  echo "postgres_backup_age_seconds=$backup_age_seconds"
  echo "postgres_cloud_apply=disabled; rollback requires restoring a checkpoint"
  if [[ "$MODE" == "--check" ]]; then
    if [[ "$postgres_backup_timer" != "active" || "$postgres_backup_enabled" != "enabled" || ! -s "$backup_path" || "$backup_age_seconds" -lt 0 || "$backup_age_seconds" -gt 2700 ]]; then
      echo "PostgreSQL backup checkpoint is not healthy" >&2
      exit 1
    fi
  fi
else
  "${SYNC_ROOT}/postgres-standby/postgres-standby-status.sh" "${check_argument[@]}"
fi
forward_subscription="$(docker exec supabase-db psql -X -v ON_ERROR_STOP=1 -U supabase_admin -d postgres -Atc "SELECT CASE WHEN subenabled THEN 'enabled' ELSE 'disabled' END FROM pg_subscription WHERE subname='sellton_cloud_to_hetzner'")"
if [[ -s "$RETIRED_MARKER" ]]; then
  echo "postgres_forward_replication=retired"
elif [[ -n "$forward_subscription" ]]; then
  echo "postgres_forward_replication=${forward_subscription}; retirement pending after Hetzner acceptance"
else
  echo "postgres_forward_replication=subscription missing; retirement marker missing"
  if [[ "$MODE" == "--check" ]]; then
    echo "PostgreSQL forward replication retirement state is ambiguous" >&2
    exit 1
  fi
fi

echo "=== Storage: Hetzner -> cloud ==="
"${SYNC_ROOT}/storage-standby/storage-standby-status.sh" "${check_argument[@]}"

echo "=== MongoDB: Hetzner -> Atlas ==="
mongo_service="$(systemctl is-active sellton-mongodb-standby.service 2>/dev/null || true)"
mongo_enabled="$(systemctl is-enabled sellton-mongodb-standby.service 2>/dev/null || true)"
echo "mongodb_standby_service=$mongo_service"
echo "mongodb_standby_enabled=$mongo_enabled"
if [[ -r "$MONGO_STATE" ]]; then
  MONGO_MIRROR_STATE_PATH="$MONGO_STATE" node /opt/sellton/gmail-api-prod/scripts/mongodb-live-mirror.js --status
  mongo_values="$(STATE_FILE="$MONGO_STATE" node -e '
    const {BSON}=require("/opt/sellton/gmail-api-prod/node_modules/mongodb");
    const fs=require("fs");
    const state=BSON.EJSON.parse(fs.readFileSync(process.env.STATE_FILE,"utf8"),{relaxed:true});
    process.stdout.write(`${state.phase}|${state.initializationMode || "copy"}|${state.lagSeconds}|${state.lastError ? 1 : 0}`);
  ')"
else
  mongo_values="missing|missing|-1|1"
  echo "MongoDB standby status unavailable"
fi

if [[ "$MODE" == "--check" ]]; then
  IFS='|' read -r mongo_phase mongo_mode mongo_lag mongo_error <<< "$mongo_values"
  if [[ "$mongo_service" != "active" || "$mongo_enabled" != "enabled" || "$mongo_phase" != "live" || "$mongo_mode" != "stream" || "$mongo_lag" -gt 5 || "$mongo_error" != "0" ]]; then
    echo "MongoDB standby is not ready: service=$mongo_service enabled=$mongo_enabled phase=$mongo_phase mode=$mongo_mode lag=$mongo_lag error=$mongo_error" >&2
    exit 1
  fi
  echo "STANDBY CHECK PASSED"
fi
