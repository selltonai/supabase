#!/usr/bin/env bash
set -Eeuo pipefail

MODE="${1:-status}"
SLOT="sellton_hetzner_to_cloud"
ORIGIN="sellton_hetzner_to_cloud"
CLOUD_ENV="/root/sellton-source-pg.env"

local_psql() {
  docker exec -i supabase-db psql -X -v ON_ERROR_STOP=1 -U supabase_admin -d postgres "$@"
}

set -a
# shellcheck disable=SC1090
source "$CLOUD_ENV"
set +a

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

service_state="$(systemctl is-active sellton-postgres-standby.service 2>/dev/null || true)"
slot_values="$(local_psql -Atc "SELECT active::text || '|' || coalesce(pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn)::bigint, -1) FROM pg_replication_slots WHERE slot_name='$SLOT'")"
IFS='|' read -r slot_active retained_lag_bytes <<< "$slot_values"
sentinel_apply="missing"
if docker ps --format '{{.Names}}' | grep -qx sellton-postgres-standby; then
  sentinel_apply="$(docker exec sellton-postgres-standby sqlite3 /work/schema/source.db "SELECT CASE WHEN apply=1 THEN 'enabled' ELSE 'disabled' END FROM sentinel WHERE id=1;" 2>/dev/null || echo missing)"
fi
target_remote_lsn="$(cloud_psql -Atc "SELECT remote_lsn FROM pg_replication_origin_status WHERE external_id='$ORIGIN'" 2>/dev/null || true)"
apply_lag_bytes="unknown"
if [[ -n "$target_remote_lsn" ]]; then
  apply_lag_bytes="$(local_psql -At -v remote_lsn="$target_remote_lsn" -c "SELECT greatest(pg_wal_lsn_diff(pg_current_wal_lsn(), :'remote_lsn'::pg_lsn), 0)::bigint")"
fi

cat <<EOF
postgres_standby_service=$service_state
postgres_standby_slot_active=${slot_active:-missing}
postgres_standby_retained_lag_bytes=${retained_lag_bytes:-missing}
postgres_standby_apply=$sentinel_apply
postgres_standby_target_remote_lsn=${target_remote_lsn:-none-yet}
postgres_standby_apply_lag_bytes=$apply_lag_bytes
EOF

if [[ "$MODE" == "--check" ]]; then
  if [[ "$service_state" != "active" || "$slot_active" != "t" || "$sentinel_apply" != "enabled" ]]; then
    echo "PostgreSQL standby is not active and applying" >&2
    exit 1
  fi
  if [[ -z "$retained_lag_bytes" || "$retained_lag_bytes" == "-1" || "$retained_lag_bytes" -gt 1048576 ]]; then
    echo "PostgreSQL standby retained lag is too high: ${retained_lag_bytes:-missing}" >&2
    exit 1
  fi
  if [[ "$apply_lag_bytes" != "unknown" && "$apply_lag_bytes" -gt 1048576 ]]; then
    echo "PostgreSQL standby apply lag is too high: $apply_lag_bytes" >&2
    exit 1
  fi
elif [[ "$MODE" != "status" ]]; then
  echo "usage: $0 [--check]" >&2
  exit 2
fi

unset PGPASSWORD
