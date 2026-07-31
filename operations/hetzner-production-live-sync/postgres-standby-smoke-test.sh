#!/usr/bin/env bash
set -Eeuo pipefail

umask 077

SUPABASE_ENV="/opt/sellton/supabase/.env"
SOURCE_DATABASE="sellton_standby_probe_source"
TARGET_DATABASE="sellton_standby_probe_target"
CONTAINER="sellton-postgres-standby-probe"
SLOT="sellton_standby_probe"
ORIGIN="sellton_standby_probe"
TEST_ROOT="/opt/sellton/live-sync/postgres-standby/probe"
IMAGE="dimitri/pgcopydb@sha256:e254421511054f9b5d9030f38454c6221bdf6ef5ab6a7e1f3e830744a7b9dfac"

admin_psql() {
  docker exec -i supabase-db psql -X -v ON_ERROR_STOP=1 -U supabase_admin -d postgres "$@"
}

cleanup() {
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  admin_psql -c "SELECT pg_replication_origin_drop('$ORIGIN') FROM pg_replication_origin WHERE roname='$ORIGIN'" >/dev/null 2>&1 || true
  admin_psql -c "DROP DATABASE IF EXISTS $SOURCE_DATABASE WITH (FORCE)" >/dev/null 2>&1 || true
  admin_psql -c "DROP DATABASE IF EXISTS $TARGET_DATABASE WITH (FORCE)" >/dev/null 2>&1 || true
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

set -a
# shellcheck disable=SC1090
source "$SUPABASE_ENV"
set +a

encoded_password="$(VALUE="$POSTGRES_PASSWORD" node -e 'process.stdout.write(encodeURIComponent(process.env.VALUE))')"
source_uri="postgresql://supabase_admin:${encoded_password}@supabase-db:${POSTGRES_PORT}/${SOURCE_DATABASE}?sslmode=disable"
target_uri="postgresql://supabase_admin:${encoded_password}@supabase-db:${POSTGRES_PORT}/${TARGET_DATABASE}?sslmode=disable"

cleanup
admin_psql -c "CREATE DATABASE $SOURCE_DATABASE"
admin_psql -c "CREATE DATABASE $TARGET_DATABASE"
for database_name in "$SOURCE_DATABASE" "$TARGET_DATABASE"; do
  docker exec -i supabase-db psql -X -v ON_ERROR_STOP=1 -U supabase_admin -d "$database_name" <<'SQL'
CREATE TABLE public.probe (
  id bigint PRIMARY KEY,
  value text NOT NULL
);
INSERT INTO public.probe (id, value) VALUES (1, 'baseline');
SQL
done

install -d -m 700 "$TEST_ROOT"
install -d -m 700 -o 999 -g 102 "${TEST_ROOT}/work"
{
  printf 'PGCOPYDB_SOURCE_PGURI=%s\n' "$source_uri"
  printf 'PGCOPYDB_TARGET_PGURI=%s\n' "$target_uri"
} > "${TEST_ROOT}/pgcopydb.env"
chmod 600 "${TEST_ROOT}/pgcopydb.env"
printf '%s\n' '[include-only-table]' 'public.probe' > "${TEST_ROOT}/filters.ini"
chmod 644 "${TEST_ROOT}/filters.ini"

docker run -d \
  --name "$CONTAINER" \
  --network supabase_default \
  --env-file "${TEST_ROOT}/pgcopydb.env" \
  --volume "${TEST_ROOT}/work:/work" \
  --volume "${TEST_ROOT}/filters.ini:/config/filters.ini:ro" \
  "$IMAGE" pgcopydb follow \
    --dir /work \
    --filters /config/filters.ini \
    --slot-name "$SLOT" \
    --origin "$ORIGIN" \
    --not-consistent \
    --create-slot >/dev/null

for _ in $(seq 1 60); do
  if docker exec supabase-db psql -X -U supabase_admin -d "$SOURCE_DATABASE" -Atc "SELECT active FROM pg_replication_slots WHERE slot_name='$SLOT'" | grep -qx t; then
    break
  fi
  if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
    docker logs "$CONTAINER" >&2 || true
    exit 1
  fi
  sleep 1
done
slot_active="$(docker exec supabase-db psql -X -U supabase_admin -d "$SOURCE_DATABASE" -Atc "SELECT active FROM pg_replication_slots WHERE slot_name='$SLOT'")"
if [[ "$slot_active" != "t" ]]; then
  echo "standby probe replication slot did not become active" >&2
  exit 1
fi

"/opt/sellton/live-sync/postgres-standby/postgres-standby-enable-apply.sh" "$CONTAINER" >/dev/null

docker exec supabase-db psql -X -v ON_ERROR_STOP=1 -U supabase_admin -d "$SOURCE_DATABASE" -c "INSERT INTO public.probe (id, value) VALUES (2, 'inserted')" >/dev/null
for _ in $(seq 1 60); do
  replicated_value="$(docker exec supabase-db psql -X -U supabase_admin -d "$TARGET_DATABASE" -Atc "SELECT value FROM public.probe WHERE id=2")"
  [[ "$replicated_value" == "inserted" ]] && break
  sleep 1
done
[[ "${replicated_value:-}" == "inserted" ]]

docker exec supabase-db psql -X -v ON_ERROR_STOP=1 -U supabase_admin -d "$SOURCE_DATABASE" -c "UPDATE public.probe SET value='updated' WHERE id=2; DELETE FROM public.probe WHERE id=1" >/dev/null
for _ in $(seq 1 60); do
  target_state="$(docker exec supabase-db psql -X -U supabase_admin -d "$TARGET_DATABASE" -Atc "SELECT string_agg(id||':'||value, ',' ORDER BY id) FROM public.probe")"
  [[ "$target_state" == "2:updated" ]] && break
  sleep 1
done
if [[ "${target_state:-}" != "2:updated" ]]; then
  echo "unexpected standby probe target state: ${target_state:-missing}" >&2
  exit 1
fi

unset POSTGRES_PASSWORD encoded_password source_uri target_uri
echo "PostgreSQL standby smoke test passed: insert/update/delete replicated"
