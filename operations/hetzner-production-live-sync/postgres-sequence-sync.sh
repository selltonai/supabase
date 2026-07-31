#!/usr/bin/env bash
set -Eeuo pipefail

umask 077

MODE="${1:-}"
CLOUD_ENV="/root/sellton-source-pg.env"
SQL_FILE="$(mktemp)"

cleanup() {
  rm -f "$SQL_FILE"
}
trap cleanup EXIT

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

local_psql() {
  docker exec -i supabase-db psql -X -v ON_ERROR_STOP=1 -U supabase_admin -d postgres "$@"
}

SEQUENCE_SQL="
SELECT format(
  'SELECT pg_catalog.setval(%L::regclass, %s, true);',
  format('%I.%I', schemaname, sequencename),
  last_value
)
FROM pg_sequences
WHERE schemaname IN ('public', 'auth')
  AND last_value IS NOT NULL
ORDER BY schemaname, sequencename;
"

case "$MODE" in
  cloud-to-hetzner)
    cloud_psql -Atc "$SEQUENCE_SQL" > "$SQL_FILE"
    local_psql < "$SQL_FILE"
    ;;
  hetzner-to-cloud)
    local_psql -Atc "$SEQUENCE_SQL" > "$SQL_FILE"
    cloud_psql < "$SQL_FILE"
    ;;
  *)
    echo "usage: $0 cloud-to-hetzner|hetzner-to-cloud" >&2
    exit 2
    ;;
esac

unset PGPASSWORD
echo "PostgreSQL sequences synchronized: $MODE"
