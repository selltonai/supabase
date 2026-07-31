#!/usr/bin/env bash
set -Eeuo pipefail

SYNC_ROOT="/opt/sellton/live-sync/postgres-standby"
WORK_DIR="${SYNC_ROOT}/work"
CONNECTION_ENV="${SYNC_ROOT}/pgcopydb.env"
FILTERS="${SYNC_ROOT}/postgres-standby-filters.ini"
SOURCE_READY_MARKER="/opt/sellton/live-sync/STANDBY_SOURCE_READY"
IMAGE="dimitri/pgcopydb@sha256:e254421511054f9b5d9030f38454c6221bdf6ef5ab6a7e1f3e830744a7b9dfac"
SLOT="sellton_hetzner_to_cloud"
ORIGIN="sellton_hetzner_to_cloud"

if [[ ! -s "$SOURCE_READY_MARKER" ]]; then
  echo "standby source-ready marker is missing: $SOURCE_READY_MARKER" >&2
  exit 1
fi
if [[ ! -s "$CONNECTION_ENV" || ! -s "$FILTERS" ]]; then
  echo "PostgreSQL standby synchronization is not prepared" >&2
  exit 1
fi

forward_enabled="$(docker exec supabase-db psql -X -v ON_ERROR_STOP=1 -U supabase_admin -d postgres -Atc "SELECT coalesce(bool_or(subenabled), false) FROM pg_subscription WHERE subname='sellton_cloud_to_hetzner'")"
if [[ "$forward_enabled" == "t" ]]; then
  echo "refusing reverse standby while cloud-to-Hetzner subscription is enabled" >&2
  exit 1
fi

slot_exists="$(docker exec supabase-db psql -X -v ON_ERROR_STOP=1 -U supabase_admin -d postgres -Atc "SELECT count(*) FROM pg_replication_slots WHERE slot_name='$SLOT'")"
work_has_state="false"
if find "$WORK_DIR" -mindepth 1 -print -quit | grep -q .; then
  work_has_state="true"
fi

follow_arguments=(
  follow
  --dir /work
  --filters /config/postgres-standby-filters.ini
  --slot-name "$SLOT"
  --origin "$ORIGIN"
  --not-consistent
)

if [[ "$slot_exists" == "0" && "$work_has_state" == "false" ]]; then
  follow_arguments+=(--create-slot)
elif [[ "$slot_exists" == "1" && "$work_has_state" == "true" ]]; then
  follow_arguments+=(--resume)
else
  echo "PostgreSQL standby slot/work state mismatch: slot_exists=$slot_exists work_has_state=$work_has_state" >&2
  exit 1
fi

exec docker run --rm \
  --name sellton-postgres-standby \
  --network supabase_default \
  --env-file "$CONNECTION_ENV" \
  --volume "${WORK_DIR}:/work" \
  --volume "${FILTERS}:/config/postgres-standby-filters.ini:ro" \
  "$IMAGE" pgcopydb "${follow_arguments[@]}"
