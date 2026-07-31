#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${1:-}" != "--source-ready" ]]; then
  echo "usage: $0 --source-ready [--postgres-backup-only]" >&2
  exit 2
fi

POSTGRES_MODE="live"
if [[ "${2:-}" == "--postgres-backup-only" ]]; then
  POSTGRES_MODE="backup-only"
elif [[ -n "${2:-}" ]]; then
  echo "usage: $0 --source-ready [--postgres-backup-only]" >&2
  exit 2
fi

SYNC_ROOT="/opt/sellton/live-sync"
SOURCE_READY_MARKER="${SYNC_ROOT}/STANDBY_SOURCE_READY"
STANDBY_MARKER="${SYNC_ROOT}/STANDBY_ENABLED"
MONGO_STATE="/var/lib/sellton-mongodb-standby/state.json"
GMAIL_ROOT="/opt/sellton/gmail-api-prod"
POSTGRES_MODE_MARKER="${SYNC_ROOT}/POSTGRES_STANDBY_MODE"

if [[ ! -s "$SOURCE_READY_MARKER" ]]; then
  echo "standby source-ready marker is missing: $SOURCE_READY_MARKER" >&2
  exit 1
fi
marker_age="$(( $(date +%s) - $(stat -c %Y "$SOURCE_READY_MARKER") ))"
if (( marker_age < 0 || marker_age > 1800 )); then
  echo "standby source-ready marker must be less than 30 minutes old; current age=${marker_age}s" >&2
  exit 1
fi
if [[ -s "$STANDBY_MARKER" ]]; then
  "${SYNC_ROOT}/production-standby-status.sh" --check
  echo "Hetzner-to-cloud standby is already enabled"
  exit 0
fi

forward_subscription_enabled="$(docker exec supabase-db psql -X -v ON_ERROR_STOP=1 -U supabase_admin -d postgres -Atc "SELECT coalesce(bool_or(subenabled), false) FROM pg_subscription WHERE subname='sellton_cloud_to_hetzner'")"
if [[ "$forward_subscription_enabled" == "t" ]]; then
  echo "cloud-to-Hetzner PostgreSQL subscription is still enabled" >&2
  exit 1
fi
if systemctl is-active --quiet sellton-mongodb-live-mirror.service || systemctl is-enabled --quiet sellton-mongodb-live-mirror.service; then
  echo "cloud-to-Hetzner MongoDB mirror is still active or enabled" >&2
  exit 1
fi
if systemctl is-active --quiet sellton-storage-live-sync.timer || systemctl is-enabled --quiet sellton-storage-live-sync.timer; then
  echo "cloud-to-Hetzner Storage mirror is still active or enabled" >&2
  exit 1
fi
if systemctl is-active --quiet sellton-gmail-api-prod.service; then
  echo "Hetzner Gmail API must remain stopped while standby capture is initialized" >&2
  exit 1
fi

standby_complete="false"
cleanup_partial_start() {
  if [[ "$standby_complete" == "true" ]]; then
    return
  fi
  echo "standby initialization failed; stopping partially started standby services" >&2
  systemctl disable --now sellton-mongodb-standby.service >/dev/null 2>&1 || true
  systemctl disable --now sellton-storage-standby.timer >/dev/null 2>&1 || true
  systemctl stop sellton-storage-standby.service >/dev/null 2>&1 || true
  systemctl disable --now sellton-postgres-standby.service >/dev/null 2>&1 || true
  systemctl disable --now sellton-postgres-backup-standby.timer >/dev/null 2>&1 || true
  rm -f "$POSTGRES_MODE_MARKER"
}
trap cleanup_partial_start EXIT

printf '%s\n' "$POSTGRES_MODE" > "$POSTGRES_MODE_MARKER"
chmod 600 "$POSTGRES_MODE_MARKER"
if [[ "$POSTGRES_MODE" == "backup-only" ]]; then
  echo "creating PostgreSQL backup checkpoint; hosted Supabase blocks replication-origin apply"
  "${SYNC_ROOT}/postgres-standby/postgres-standby-backup.sh"
  systemctl enable --now sellton-postgres-backup-standby.timer
else
  echo "preparing PostgreSQL Hetzner-to-cloud standby"
  "${SYNC_ROOT}/postgres-standby/postgres-standby-prepare.sh"
  systemctl enable --now sellton-postgres-standby.service
  for _ in $(seq 1 90); do
    slot_active="$(docker exec supabase-db psql -X -U supabase_admin -d postgres -Atc "SELECT active FROM pg_replication_slots WHERE slot_name='sellton_hetzner_to_cloud'" 2>/dev/null || true)"
    [[ "$slot_active" == "t" ]] && break
    if ! systemctl is-active --quiet sellton-postgres-standby.service; then
      journalctl -u sellton-postgres-standby.service -n 50 --no-pager >&2 || true
      exit 1
    fi
    sleep 1
  done
  if [[ "${slot_active:-}" != "t" ]]; then
    echo "PostgreSQL standby replication slot did not become active" >&2
    exit 1
  fi
  "${SYNC_ROOT}/postgres-standby/postgres-standby-enable-apply.sh"
fi

echo "seeding and starting Storage Hetzner-to-cloud standby"
"${SYNC_ROOT}/storage-standby/storage-standby-sync-run.sh" seed
systemctl enable --now sellton-storage-standby.timer

echo "starting MongoDB Hetzner-to-Atlas stream-only standby"
install -d -m 700 /var/lib/sellton-mongodb-standby
systemctl enable --now sellton-mongodb-standby.service
for _ in $(seq 1 180); do
  mongo_values="$(STATE_FILE="$MONGO_STATE" node -e '
    const {BSON}=require("/opt/sellton/gmail-api-prod/node_modules/mongodb");
    const fs=require("fs");
    if (!fs.existsSync(process.env.STATE_FILE)) process.exit(0);
    const state=BSON.EJSON.parse(fs.readFileSync(process.env.STATE_FILE,"utf8"),{relaxed:true});
    process.stdout.write(`${state.phase}|${state.initializationMode || "copy"}|${state.lagSeconds}|${state.lastError ? 1 : 0}`);
  ' 2>/dev/null || true)"
  IFS='|' read -r mongo_phase mongo_mode mongo_lag mongo_error <<< "$mongo_values"
  if [[ "$mongo_phase" == "live" && "$mongo_mode" == "stream" && "$mongo_lag" -le 5 && "$mongo_error" == "0" ]]; then
    break
  fi
  if ! systemctl is-active --quiet sellton-mongodb-standby.service; then
    journalctl -u sellton-mongodb-standby.service -n 50 --no-pager >&2 || true
    exit 1
  fi
  sleep 1
done
if [[ "${mongo_phase:-}" != "live" || "${mongo_mode:-}" != "stream" || "${mongo_lag:--1}" -gt 5 || "${mongo_error:-1}" != "0" ]]; then
  echo "MongoDB standby did not become live: phase=${mongo_phase:-missing} mode=${mongo_mode:-missing} lag=${mongo_lag:-missing} error=${mongo_error:-missing}" >&2
  exit 1
fi

GMAIL_ROOT="$GMAIL_ROOT" MONGO_STATE="$MONGO_STATE" node <<'NODE'
const fs = require('fs');
const { execFileSync } = require('child_process');
const dotenv = require('/opt/sellton/gmail-api-prod/node_modules/dotenv');

const gmailRoot = process.env.GMAIL_ROOT;
const environment = {
  ...process.env,
  ...dotenv.parse(fs.readFileSync('/root/sellton-source-mongo.env')),
  ...dotenv.parse(fs.readFileSync(`${gmailRoot}/.env`)),
  MONGO_MIRROR_DIRECTION: 'hetzner-to-cloud',
  MONGO_MIRROR_INITIALIZATION_MODE: 'stream',
  MONGO_MIRROR_ALLOW_TARGET_SUPERSET: 'true',
  MONGO_MIRROR_DATABASE: 'production',
  MONGO_MIRROR_STATE_PATH: process.env.MONGO_STATE,
};
execFileSync(process.execPath, [`${gmailRoot}/scripts/mongodb-live-mirror.js`, '--verify'], { env: environment, stdio: 'ignore' });
NODE

"${SYNC_ROOT}/production-standby-status.sh" --check
date -u +%FT%TZ > "$STANDBY_MARKER"
chmod 600 "$STANDBY_MARKER"
standby_complete="true"
echo "HETZNER-TO-CLOUD STANDBY ENABLED"
