#!/usr/bin/env bash
set -Eeuo pipefail

umask 077

SYNC_ROOT="/opt/sellton/live-sync/postgres-standby"
SUPABASE_ENV="/opt/sellton/supabase/.env"
CLOUD_ENV="/root/sellton-source-pg.env"
CONNECTION_ENV="${SYNC_ROOT}/pgcopydb.env"
IMAGE="dimitri/pgcopydb@sha256:e254421511054f9b5d9030f38454c6221bdf6ef5ab6a7e1f3e830744a7b9dfac"

if systemctl is-active --quiet sellton-postgres-standby.service; then
  echo "refusing preparation while PostgreSQL standby sync is active" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$SUPABASE_ENV"
set +a

required_local_variables=(POSTGRES_PASSWORD POSTGRES_DB POSTGRES_PORT)
for variable_name in "${required_local_variables[@]}"; do
  if [[ -z "${!variable_name:-}" ]]; then
    echo "missing local Supabase variable: $variable_name" >&2
    exit 1
  fi
done

local_password="$(VALUE="$POSTGRES_PASSWORD" node -e 'process.stdout.write(encodeURIComponent(process.env.VALUE))')"
local_database="$(VALUE="$POSTGRES_DB" node -e 'process.stdout.write(encodeURIComponent(process.env.VALUE))')"
local_uri="postgresql://supabase_admin:${local_password}@supabase-db:${POSTGRES_PORT}/${local_database}?sslmode=disable"

unset PGHOST PGPORT PGDATABASE PGUSER PGPASSWORD PGSSLMODE
set -a
# shellcheck disable=SC1090
source "$CLOUD_ENV"
set +a

required_cloud_variables=(PGHOST PGPORT PGDATABASE PGUSER PGPASSWORD PGSSLMODE)
for variable_name in "${required_cloud_variables[@]}"; do
  if [[ -z "${!variable_name:-}" ]]; then
    echo "missing hosted PostgreSQL variable: $variable_name" >&2
    exit 1
  fi
done

cloud_user="$(VALUE="$PGUSER" node -e 'process.stdout.write(encodeURIComponent(process.env.VALUE))')"
cloud_password="$(VALUE="$PGPASSWORD" node -e 'process.stdout.write(encodeURIComponent(process.env.VALUE))')"
cloud_database="$(VALUE="$PGDATABASE" node -e 'process.stdout.write(encodeURIComponent(process.env.VALUE))')"
cloud_uri="postgresql://${cloud_user}:${cloud_password}@${PGHOST}:${PGPORT}/${cloud_database}?sslmode=${PGSSLMODE}"

install -d -m 700 "$SYNC_ROOT"
install -d -m 700 -o 999 -g 102 "${SYNC_ROOT}/work"
{
  printf 'PGCOPYDB_SOURCE_PGURI=%s\n' "$local_uri"
  printf 'PGCOPYDB_TARGET_PGURI=%s\n' "$cloud_uri"
} > "$CONNECTION_ENV"
chmod 600 "$CONNECTION_ENV"

echo "testing pgcopydb source and target connections"
docker run --rm --network supabase_default --env-file "$CONNECTION_ENV" "$IMAGE" sh -c 'psql "$PGCOPYDB_SOURCE_PGURI" -X -v ON_ERROR_STOP=1 -Atc "SELECT current_database()" >/dev/null'
docker run --rm --network supabase_default --env-file "$CONNECTION_ENV" "$IMAGE" sh -c 'psql "$PGCOPYDB_TARGET_PGURI" -X -v ON_ERROR_STOP=1 -Atc "SELECT current_database()" >/dev/null'

unset POSTGRES_PASSWORD PGPASSWORD local_password local_uri cloud_password cloud_uri
echo "PostgreSQL Hetzner-to-cloud standby prepared but not started"
