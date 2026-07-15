#!/usr/bin/env bash
set -Eeuo pipefail

if [[ "${1:-}" != "--hetzner-primary-confirmed" ]]; then
  echo "usage: $0 --hetzner-primary-confirmed" >&2
  echo "Run only after production writes on Hetzner and all rollback standbys are verified." >&2
  exit 2
fi

umask 077

SYNC_ROOT="/opt/sellton/live-sync"
CLOUD_ENV="/root/sellton-source-pg.env"
CUTOVER_MARKER="${SYNC_ROOT}/CUTOVER_COMPLETE"
STANDBY_MARKER="${SYNC_ROOT}/STANDBY_ENABLED"
RETIRED_MARKER="${SYNC_ROOT}/FORWARD_REPLICATION_RETIRED"
SUBSCRIPTION="sellton_cloud_to_hetzner"
PUBLICATION="sellton_hetzner_forward"

if [[ ! -s "$CUTOVER_MARKER" || ! -s "$STANDBY_MARKER" ]]; then
  echo "cutover and standby markers are required before retiring forward replication" >&2
  exit 1
fi
if [[ ! -r "$CLOUD_ENV" ]]; then
  echo "missing cloud PostgreSQL environment: $CLOUD_ENV" >&2
  exit 1
fi
if systemctl is-active --quiet sellton-mongodb-live-mirror.service || systemctl is-enabled --quiet sellton-mongodb-live-mirror.service; then
  echo "MongoDB forward mirror is still active or enabled" >&2
  exit 1
fi
if systemctl is-active --quiet sellton-storage-live-sync.timer || systemctl is-enabled --quiet sellton-storage-live-sync.timer; then
  echo "Storage forward mirror is still active or enabled" >&2
  exit 1
fi

"${SYNC_ROOT}/production-standby-status.sh" --check

set -a
# shellcheck disable=SC1090
source "$CLOUD_ENV"
set +a

local_psql() {
  docker exec -i supabase-db psql -X -v ON_ERROR_STOP=1 -U supabase_admin -d postgres "$@"
}

cloud_psql() {
  docker exec -i \
    -e PGHOST="$PGHOST" \
    -e PGPORT="$PGPORT" \
    -e PGDATABASE="$PGDATABASE" \
    -e PGUSER="$PGUSER" \
    -e PGPASSWORD="$PGPASSWORD" \
    -e PGSSLMODE="$PGSSLMODE" \
    supabase-db psql -X -v ON_ERROR_STOP=1 "$@"
}

subscription_enabled="$(local_psql -Atc "SELECT subenabled FROM pg_subscription WHERE subname='$SUBSCRIPTION'")"
if [[ -n "$subscription_enabled" && "$subscription_enabled" != "f" ]]; then
  echo "forward PostgreSQL subscription must be disabled before retirement" >&2
  exit 1
fi

slot_active="$(cloud_psql -Atc "SELECT active::text FROM pg_replication_slots WHERE slot_name='$SUBSCRIPTION'")"
if [[ "$slot_active" == "t" ]]; then
  echo "forward PostgreSQL replication slot is still active" >&2
  exit 1
fi

if [[ -n "$subscription_enabled" ]]; then
  echo "detaching and dropping the disabled Hetzner forward subscription"
  local_psql -c "ALTER SUBSCRIPTION $SUBSCRIPTION SET (slot_name = NONE)"
  local_psql -c "DROP SUBSCRIPTION $SUBSCRIPTION"
fi

echo "dropping the obsolete cloud forward slot and publication"
cloud_psql <<SQL
SELECT pg_drop_replication_slot('$SUBSCRIPTION')
WHERE EXISTS (
  SELECT 1
  FROM pg_replication_slots
  WHERE slot_name = '$SUBSCRIPTION'
    AND NOT active
);
DROP PUBLICATION IF EXISTS $PUBLICATION;
SQL

if [[ "$(local_psql -Atc "SELECT count(*) FROM pg_subscription WHERE subname='$SUBSCRIPTION'")" != "0" ]]; then
  echo "forward subscription still exists on Hetzner" >&2
  exit 1
fi
if [[ "$(cloud_psql -Atc "SELECT count(*) FROM pg_replication_slots WHERE slot_name='$SUBSCRIPTION'")" != "0" ]]; then
  echo "forward replication slot still exists in cloud PostgreSQL" >&2
  exit 1
fi
if [[ "$(cloud_psql -Atc "SELECT count(*) FROM pg_publication WHERE pubname='$PUBLICATION'")" != "0" ]]; then
  echo "forward publication still exists in cloud PostgreSQL" >&2
  exit 1
fi

date -u +%FT%TZ > "$RETIRED_MARKER"
chmod 600 "$RETIRED_MARKER"
unset PGPASSWORD
echo "FORWARD REPLICATION RETIRED; HETZNER-TO-CLOUD STANDBY REMAINS ACTIVE"
