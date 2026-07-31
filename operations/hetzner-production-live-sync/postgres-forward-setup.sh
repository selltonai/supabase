#!/usr/bin/env bash
set -Eeuo pipefail

umask 077

SUPABASE_ROOT="/opt/sellton/supabase"
SYNC_ROOT="/opt/sellton/live-sync/postgres"
BACKUP_ROOT="/opt/sellton/backups/supabase/prod"
SOURCE_ENV="/root/sellton-source-pg.env"
PUBLICATION="sellton_hetzner_forward"
SUBSCRIPTION="sellton_cloud_to_hetzner"
RUN_ID="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="${SYNC_ROOT}/setup-${RUN_ID}.log"
TARGET_BACKUP="${BACKUP_ROOT}/hetzner-before-live-sync-${RUN_ID}.dump"

mkdir -p "$SYNC_ROOT" "$BACKUP_ROOT"
exec > >(tee -a "$LOG_FILE") 2>&1

if [[ ! -r "$SOURCE_ENV" ]]; then
  echo "missing source PostgreSQL environment: $SOURCE_ENV" >&2
  exit 1
fi

if systemctl is-active --quiet sellton-gmail-api-prod.service; then
  echo "refusing setup while Hetzner production Gmail API is active" >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$SOURCE_ENV"
set +a

required_source_variables=(PGHOST PGPORT PGDATABASE PGUSER PGPASSWORD PGSSLMODE)
for variable_name in "${required_source_variables[@]}"; do
  if [[ -z "${!variable_name:-}" ]]; then
    echo "missing source PostgreSQL variable: $variable_name" >&2
    exit 1
  fi
done

source_psql() {
  docker exec -i \
    -e PGHOST="$PGHOST" \
    -e PGPORT="$PGPORT" \
    -e PGDATABASE="$PGDATABASE" \
    -e PGUSER="$PGUSER" \
    -e PGPASSWORD="$PGPASSWORD" \
    -e PGSSLMODE="$PGSSLMODE" \
    supabase-db psql -X -v ON_ERROR_STOP=1 "$@"
}

target_psql() {
  docker exec -i supabase-db psql -X -v ON_ERROR_STOP=1 -U supabase_admin -d postgres "$@"
}

quote_conninfo_value() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\'/\\\'}"
  printf "'%s'" "$value"
}

echo "checking source and target replication state"
if [[ "$(source_psql -Atc "SELECT count(*) FROM pg_publication WHERE pubname = '$PUBLICATION'")" != "0" ]]; then
  echo "source publication already exists: $PUBLICATION" >&2
  exit 1
fi

if [[ "$(target_psql -Atc "SELECT count(*) FROM pg_subscription WHERE subname = '$SUBSCRIPTION'")" != "0" ]]; then
  echo "target subscription already exists: $SUBSCRIPTION" >&2
  exit 1
fi

echo "creating target rollback backup: $TARGET_BACKUP"
docker exec supabase-db pg_dump -U postgres -d postgres -Fc > "$TARGET_BACKUP"
test -s "$TARGET_BACKUP"

echo "restoring missing auth.identities primary key on target"
target_psql <<'SQL'
SET ROLE supabase_auth_admin;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conrelid = 'auth.identities'::regclass
      AND contype = 'p'
  ) THEN
    ALTER TABLE auth.identities ADD CONSTRAINT identities_pkey PRIMARY KEY (id);
  END IF;
END
$$;
RESET ROLE;
SQL

echo "recording replicated table inventory"
source_psql -At <<'SQL' > "${SYNC_ROOT}/replicated-tables.txt"
SELECT format('%I.%I', schemaname, tablename)
FROM pg_tables
WHERE schemaname IN ('public', 'auth', 'storage')
  AND NOT (schemaname = 'auth' AND tablename = 'schema_migrations')
  AND NOT (schemaname = 'storage' AND tablename = 'migrations')
  AND NOT (schemaname = 'public' AND tablename IN ('backup_kan139_pipeline_stage', 'style_guidelines_backup'))
ORDER BY schemaname, tablename;
SQL

replicated_table_count="$(wc -l < "${SYNC_ROOT}/replicated-tables.txt")"
if (( replicated_table_count < 100 )); then
  echo "unexpected replicated table count: $replicated_table_count" >&2
  exit 1
fi
echo "replicated table count: $replicated_table_count"

echo "creating cloud publication"
source_psql <<SQL
SELECT format(
  'CREATE PUBLICATION %I FOR TABLE %s WITH (publish = ''insert, update, delete, truncate'')',
  '$PUBLICATION',
  string_agg(format('%I.%I', schemaname, tablename), ', ' ORDER BY schemaname, tablename)
)
FROM pg_tables
WHERE schemaname IN ('public', 'auth', 'storage')
  AND NOT (schemaname = 'auth' AND tablename = 'schema_migrations')
  AND NOT (schemaname = 'storage' AND tablename = 'migrations')
  AND NOT (schemaname = 'public' AND tablename IN ('backup_kan139_pipeline_stage', 'style_guidelines_backup'))
\gexec
SQL

echo "stopping Hetzner Supabase application services"
docker compose -f "${SUPABASE_ROOT}/docker-compose.yml" --project-directory "$SUPABASE_ROOT" stop \
  rest analytics studio kong meta imgproxy storage supavisor vector auth functions realtime

echo "clearing replicated target tables"
target_psql <<'SQL'
SELECT format(
  'TRUNCATE TABLE %s CASCADE',
  string_agg(format('%I.%I', schemaname, tablename), ', ' ORDER BY schemaname, tablename)
)
FROM pg_tables
WHERE schemaname IN ('public', 'auth', 'storage')
  AND NOT (schemaname = 'auth' AND tablename = 'schema_migrations')
  AND NOT (schemaname = 'storage' AND tablename = 'migrations')
  AND NOT (schemaname = 'public' AND tablename IN ('backup_kan139_pipeline_stage', 'style_guidelines_backup'))
\gexec
SQL

source_conninfo="host=$(quote_conninfo_value "$PGHOST") port=$(quote_conninfo_value "$PGPORT") dbname=$(quote_conninfo_value "$PGDATABASE") user=$(quote_conninfo_value "$PGUSER") password=$(quote_conninfo_value "$PGPASSWORD") sslmode=$(quote_conninfo_value "$PGSSLMODE") application_name=$(quote_conninfo_value "$SUBSCRIPTION") options=$(quote_conninfo_value '-c statement_timeout=0')"

echo "creating target subscription with initial copy enabled"
target_psql -v source_conn="$source_conninfo" <<SQL
CREATE SUBSCRIPTION $SUBSCRIPTION
CONNECTION :'source_conn'
PUBLICATION $PUBLICATION
WITH (
  copy_data = true,
  create_slot = true,
  enabled = true,
  slot_name = '$SUBSCRIPTION',
  streaming = on
);
SQL

unset source_conninfo PGPASSWORD

echo "PostgreSQL initial copy started"
echo "status: ${SYNC_ROOT}/postgres-sync-status.sh"
echo "rollback backup: $TARGET_BACKUP"
