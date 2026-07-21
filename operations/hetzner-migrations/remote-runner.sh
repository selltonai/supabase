#!/usr/bin/env bash

set -Eeuo pipefail
umask 027

log() {
  printf '[postgres-migrate-remote] %s\n' "$*"
}

fail() {
  log "ERROR: $*" >&2
  exit 1
}

[[ $# -eq 6 ]] || fail "Expected: <status|plan|apply> <stage|production> <bundle> <source-commit> <actor> <confirmation>"

readonly ACTION="$1"
readonly TARGET_ENVIRONMENT="$2"
readonly ARCHIVE_PATH="$3"
readonly SOURCE_COMMIT="$4"
readonly MIGRATION_ACTOR="$5"
readonly CONFIRMATION="$6"
readonly TEST_MODE="${HETZNER_MIGRATION_TEST_MODE:-false}"

case "$ACTION" in
  status|plan|apply) ;;
  *) fail "Unsupported action: $ACTION" ;;
esac
case "$TARGET_ENVIRONMENT" in
  stage|production) ;;
  *) fail "Unsupported environment: $TARGET_ENVIRONMENT" ;;
esac
[[ "$SOURCE_COMMIT" =~ ^[0-9a-f]{40}$ ]] || fail "Invalid source commit"
[[ "$MIGRATION_ACTOR" =~ ^[A-Za-z0-9._@-]+$ ]] || fail "Invalid migration actor"
[[ "$ARCHIVE_PATH" == /tmp/sellton-postgres-migrations-*.tar.gz || "$TEST_MODE" == true ]] || fail "Unexpected bundle path"
[[ -f "$ARCHIVE_PATH" ]] || fail "Migration bundle does not exist: $ARCHIVE_PATH"

if [[ "$ACTION" == apply && "$TARGET_ENVIRONMENT" == production && "$CONFIRMATION" != production ]]; then
  fail "Production apply confirmation is missing"
fi
if [[ "$TEST_MODE" != true && $EUID -ne 0 ]]; then
  fail "Remote migration runner must execute as root"
fi

case "$TARGET_ENVIRONMENT" in
  stage)
    readonly DEFAULT_CONTAINER="supabase-stage-db"
    readonly DEFAULT_RUNTIME_ROOT="/opt/sellton/supabase-stage"
    ;;
  production)
    readonly DEFAULT_CONTAINER="supabase-db"
    readonly DEFAULT_RUNTIME_ROOT="/opt/sellton/supabase"
    ;;
esac

readonly DATABASE_CONTAINER="${HETZNER_POSTGRES_CONTAINER:-$DEFAULT_CONTAINER}"
readonly RUNTIME_ROOT="${HETZNER_POSTGRES_RUNTIME_ROOT:-$DEFAULT_RUNTIME_ROOT}"
readonly BACKUP_ROOT="${HETZNER_POSTGRES_BACKUP_ROOT:-/opt/sellton/backups/database-migrations/$TARGET_ENVIRONMENT}"
readonly LOCK_ROOT="${HETZNER_MIGRATION_LOCK_ROOT:-/run/lock}"
readonly BACKUP_KEEP="${HETZNER_MIGRATION_BACKUP_KEEP:-3}"
readonly WORK_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/sellton-postgres-migrate-XXXXXX")"
readonly MANIFEST_PATH="$WORK_DIRECTORY/manifest.tsv"
readonly FILES_DIRECTORY="$WORK_DIRECTORY/files"
backup_path=""
artifact_path=""

cleanup() {
  rm -rf "$WORK_DIRECTORY"
  if [[ "$ARCHIVE_PATH" == /tmp/sellton-postgres-migrations-*.tar.gz ]]; then
    rm -f "$ARCHIVE_PATH"
  fi
  if [[ "$0" == /tmp/sellton-postgres-migrate-*.sh ]]; then
    rm -f "$0"
  fi
}
trap cleanup EXIT

for required_command in awk basename cat cp date df docker find flock grep mkdir mktemp mv rm sha256sum sort stat systemctl tar; do
  command -v "$required_command" >/dev/null 2>&1 || fail "Required command is unavailable: $required_command"
done
[[ "$BACKUP_KEEP" =~ ^[1-9][0-9]*$ ]] || fail "HETZNER_MIGRATION_BACKUP_KEEP must be a positive integer"

while IFS= read -r archive_entry; do
  [[ "$archive_entry" != /* && "/$archive_entry/" != *'/../'* ]] || fail "Unsafe archive entry: $archive_entry"
done < <(tar -tzf "$ARCHIVE_PATH")
while IFS= read -r archive_listing; do
  archive_mode="${archive_listing%% *}"
  [[ "${archive_mode:0:1}" == - || "${archive_mode:0:1}" == d ]] || fail "Migration bundle contains a link or special file"
done < <(tar -tvzf "$ARCHIVE_PATH")
tar --no-same-owner --no-same-permissions -xzf "$ARCHIVE_PATH" -C "$WORK_DIRECTORY"
[[ -f "$MANIFEST_PATH" ]] || fail "Bundle manifest is missing"
[[ -d "$FILES_DIRECTORY" ]] || fail "Bundle files directory is missing"

docker inspect "$DATABASE_CONTAINER" >/dev/null 2>&1 || fail "Database container is unavailable: $DATABASE_CONTAINER"

mkdir -p "$LOCK_ROOT"
exec 9>"$LOCK_ROOT/sellton-postgres-migrate-$TARGET_ENVIRONMENT.lock"
flock -n 9 || fail "Another $TARGET_ENVIRONMENT PostgreSQL migration is running"

psql_query() {
  docker exec -i "$DATABASE_CONTAINER" psql -X -v ON_ERROR_STOP=1 -U supabase_admin -d postgres "$@"
}

ledger_exists() {
  [[ "$(printf "SELECT to_regclass('sellton_migrations.applied_migrations') IS NOT NULL;\n" | psql_query -At)" == t ]]
}

ledger_hash_for_path() {
  local migration_path="$1"
  printf "SELECT sha256 FROM sellton_migrations.applied_migrations WHERE migration_path = '%s';\n" "$migration_path" | psql_query -At
}

ensure_ledger() {
  psql_query <<'SQL'
CREATE SCHEMA IF NOT EXISTS sellton_migrations AUTHORIZATION supabase_admin;
CREATE TABLE IF NOT EXISTS sellton_migrations.applied_migrations (
  migration_path text PRIMARY KEY,
  sha256 text NOT NULL CHECK (sha256 ~ '^[0-9a-f]{64}$'),
  source_commit text NOT NULL CHECK (source_commit ~ '^[0-9a-f]{40}$'),
  environment text NOT NULL CHECK (environment IN ('stage', 'production')),
  applied_by text NOT NULL,
  backup_path text,
  artifact_path text,
  applied_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE sellton_migrations.applied_migrations
  ADD COLUMN IF NOT EXISTS artifact_path text;
REVOKE ALL ON SCHEMA sellton_migrations FROM PUBLIC;
REVOKE ALL ON TABLE sellton_migrations.applied_migrations FROM PUBLIC;
SQL
}

declare -a migration_paths=()
declare -a migration_hashes=()
declare -A seen_paths=()

while IFS=$'\t' read -r migration_path expected_hash extra_field; do
  [[ -n "$migration_path" ]] || continue
  [[ -z "${extra_field:-}" ]] || fail "Malformed manifest row for $migration_path"
  [[ "$migration_path" =~ ^[A-Za-z0-9._/-]+\.sql$ ]] || fail "Invalid migration path: $migration_path"
  [[ "$expected_hash" =~ ^[0-9a-f]{64}$ ]] || fail "Invalid SHA-256 for $migration_path"
  [[ -z "${seen_paths[$migration_path]:-}" ]] || fail "Duplicate migration path: $migration_path"
  seen_paths[$migration_path]=1

  migration_file="$FILES_DIRECTORY/$migration_path"
  [[ -f "$migration_file" ]] || fail "Migration file is missing: $migration_path"
  actual_hash="$(sha256sum "$migration_file" | awk '{print $1}')"
  [[ "$actual_hash" == "$expected_hash" ]] || fail "SHA-256 mismatch for $migration_path"

  if grep -Eiq '^[[:space:]]*(BEGIN|START[[:space:]]+TRANSACTION|COMMIT|ROLLBACK)[[:space:]]*;' "$migration_file"; then
    fail "$migration_path contains transaction control; the runner owns the per-file transaction boundary"
  fi
  if grep -Eiq '^[[:space:]]*(CREATE[[:space:]]+(UNIQUE[[:space:]]+)?INDEX[[:space:]]+CONCURRENTLY|REINDEX[[:space:]].*CONCURRENTLY|REFRESH[[:space:]]+MATERIALIZED[[:space:]]+VIEW[[:space:]]+CONCURRENTLY|VACUUM|ALTER[[:space:]]+SYSTEM|(CREATE|DROP)[[:space:]]+(DATABASE|TABLESPACE))([[:space:]]|;|$)' "$migration_file"; then
    fail "$migration_path contains a non-transactional statement and must use a reviewed manual runbook"
  fi
  if grep -Eq '^[[:space:]]*\\' "$migration_file"; then
    fail "$migration_path contains a psql meta-command and must use a reviewed manual runbook"
  fi

  migration_paths+=("$migration_path")
  migration_hashes+=("$expected_hash")
done < "$MANIFEST_PATH"

if [[ "$ACTION" != status && ${#migration_paths[@]} -eq 0 ]]; then
  fail "$ACTION bundle contains no migrations"
fi

if [[ "$ACTION" == status ]]; then
  if ! ledger_exists; then
    log "No automated migrations have been recorded for $TARGET_ENVIRONMENT"
    exit 0
  fi
  psql_query -P pager=off -c "SELECT migration_path, left(sha256, 12) AS sha256, left(source_commit, 12) AS source_commit, applied_by, applied_at FROM sellton_migrations.applied_migrations WHERE environment = '$TARGET_ENVIRONMENT' ORDER BY applied_at, migration_path"
  exit 0
fi

pending_count=0
for index in "${!migration_paths[@]}"; do
  migration_path="${migration_paths[$index]}"
  expected_hash="${migration_hashes[$index]}"
  recorded_hash=""
  if ledger_exists; then
    recorded_hash="$(ledger_hash_for_path "$migration_path")"
  fi

  if [[ -z "$recorded_hash" ]]; then
    log "PENDING $migration_path sha256=${expected_hash:0:12}"
    pending_count=$((pending_count + 1))
  elif [[ "$recorded_hash" == "$expected_hash" ]]; then
    log "APPLIED $migration_path sha256=${expected_hash:0:12}"
  else
    fail "Applied migration hash drift: $migration_path recorded=$recorded_hash current=$expected_hash"
  fi
done

log "Plan summary: environment=$TARGET_ENVIRONMENT pending=$pending_count total=${#migration_paths[@]}"
if [[ "$ACTION" == plan || $pending_count -eq 0 ]]; then
  exit 0
fi

if [[ "$TARGET_ENVIRONMENT" == production && "$TEST_MODE" != true ]]; then
  if systemctl is-active --quiet sellton-postgres-standby.service; then
    fail "Production rollback standby is active; schema changes are frozen until the standby is retired or explicitly disabled through its runbook"
  fi
  enabled_subscriptions="$(printf "SELECT count(*) FROM pg_subscription WHERE subenabled;\n" | psql_query -At)"
  [[ "$enabled_subscriptions" == 0 ]] || fail "Production has $enabled_subscriptions enabled PostgreSQL subscription(s); migration apply is blocked"
fi

mkdir -p "$BACKUP_ROOT"
available_bytes="$(df -PB1 "$BACKUP_ROOT" | awk 'NR==2 {print $4}')"
database_bytes="$(printf "SELECT pg_database_size(current_database());\n" | psql_query -At)"
required_bytes=$((database_bytes + 5 * 1024 * 1024 * 1024))
(( available_bytes >= required_bytes )) || fail "Insufficient free disk for a verified backup: available=$available_bytes required=$required_bytes"

backup_timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_path="$BACKUP_ROOT/postgres-before-${SOURCE_COMMIT:0:12}-$backup_timestamp-$$.dump"
backup_temporary="$backup_path.tmp"
log "Creating pre-migration backup: $backup_path"
docker exec "$DATABASE_CONTAINER" pg_dump -Fc --no-owner --no-privileges -U supabase_admin -d postgres > "$backup_temporary"
[[ -s "$backup_temporary" ]] || fail "Pre-migration backup is empty"
docker exec -i "$DATABASE_CONTAINER" pg_restore --list < "$backup_temporary" >/dev/null
mv "$backup_temporary" "$backup_path"
(
  cd "$BACKUP_ROOT"
  sha256sum "$(basename "$backup_path")" > "$(basename "$backup_path").sha256"
)

artifact_path="$RUNTIME_ROOT/migrations-applied/automation/$backup_timestamp-${SOURCE_COMMIT:0:12}-$$"
mkdir -p "$artifact_path"
cp "$MANIFEST_PATH" "$artifact_path/manifest.tsv"
cp -a "$FILES_DIRECTORY" "$artifact_path/files"
printf 'environment=%s\nsource_commit=%s\nactor=%s\n' "$TARGET_ENVIRONMENT" "$SOURCE_COMMIT" "$MIGRATION_ACTOR" > "$artifact_path/metadata.txt"

ensure_ledger

for index in "${!migration_paths[@]}"; do
  migration_path="${migration_paths[$index]}"
  expected_hash="${migration_hashes[$index]}"
  recorded_hash="$(ledger_hash_for_path "$migration_path")"
  [[ -z "$recorded_hash" ]] || continue

  log "Applying $migration_path"
  {
    cat "$FILES_DIRECTORY/$migration_path"
    printf '\nINSERT INTO sellton_migrations.applied_migrations (migration_path, sha256, source_commit, environment, applied_by, backup_path, artifact_path) VALUES ('"'"'%s'"'"', '"'"'%s'"'"', '"'"'%s'"'"', '"'"'%s'"'"', '"'"'%s'"'"', '"'"'%s'"'"', '"'"'%s'"'"');\n' "$migration_path" "$expected_hash" "$SOURCE_COMMIT" "$TARGET_ENVIRONMENT" "$MIGRATION_ACTOR" "$backup_path" "$artifact_path"
  } | psql_query --single-transaction
done

printf "NOTIFY pgrst, 'reload schema';\n" | psql_query >/dev/null

mapfile -t retained_backups < <(find "$BACKUP_ROOT" -maxdepth 1 -type f -name 'postgres-before-*.dump' -printf '%T@ %p\n' | sort -nr | awk '{print $2}')
if (( ${#retained_backups[@]} > BACKUP_KEEP )); then
  for old_backup in "${retained_backups[@]:$BACKUP_KEEP}"; do
    rm -f "$old_backup" "$old_backup.sha256"
  done
fi

log "Apply complete: environment=$TARGET_ENVIRONMENT applied=$pending_count backup=$backup_path"
