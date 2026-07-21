#!/usr/bin/env bash

set -Eeuo pipefail

readonly TEST_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly RUNNER_DIRECTORY="$(cd "$TEST_DIRECTORY/.." && pwd)"
readonly REPOSITORY_ROOT="$(cd "$RUNNER_DIRECTORY/../.." && pwd)"
readonly FIXTURE_PATH="$TEST_DIRECTORY/fixtures/001-create-probe.sql"
readonly FIXTURE_RELATIVE_PATH="operations/hetzner-migrations/tests/fixtures/001-create-probe.sql"
readonly CONTAINER_NAME="${POSTGRES_MIGRATION_TEST_CONTAINER:-sellton-postgres-migration-test}"
readonly POSTGRES_IMAGE="${POSTGRES_MIGRATION_TEST_IMAGE:-public.ecr.aws/supabase/postgres:17.6.1.106}"
readonly SOURCE_COMMIT="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
work_directory="$(mktemp -d)"

cleanup() {
  docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
  rm -rf "$work_directory"
}
trap cleanup EXIT

docker run --rm -d --name "$CONTAINER_NAME" -e POSTGRES_PASSWORD=postgres -e PGPASSWORD=postgres "$POSTGRES_IMAGE" >/dev/null
ready_count=0
for _ in {1..90}; do
  if docker exec "$CONTAINER_NAME" pg_isready -U supabase_admin -d postgres >/dev/null 2>&1; then
    ready_count=$((ready_count + 1))
    if [[ $ready_count -ge 3 ]]; then
      break
    fi
  else
    ready_count=0
  fi
  sleep 1
done
docker exec "$CONTAINER_NAME" pg_isready -U supabase_admin -d postgres >/dev/null

mkdir -p "$work_directory/bundle/files/$(dirname "$FIXTURE_RELATIVE_PATH")" "$work_directory/backups" "$work_directory/locks" "$work_directory/runtime"
cp "$FIXTURE_PATH" "$work_directory/bundle/files/$FIXTURE_RELATIVE_PATH"
fixture_hash="$(sha256sum "$FIXTURE_PATH" | awk '{print $1}')"
printf '%s\t%s\n' "$FIXTURE_RELATIVE_PATH" "$fixture_hash" > "$work_directory/bundle/manifest.tsv"
tar -C "$work_directory/bundle" -czf "$work_directory/bundle.tar.gz" manifest.tsv files

runner_environment=(
  HETZNER_MIGRATION_TEST_MODE=true
  HETZNER_POSTGRES_CONTAINER="$CONTAINER_NAME"
  HETZNER_POSTGRES_RUNTIME_ROOT="$work_directory/runtime"
  HETZNER_POSTGRES_BACKUP_ROOT="$work_directory/backups"
  HETZNER_MIGRATION_LOCK_ROOT="$work_directory/locks"
)

env "${runner_environment[@]}" "$RUNNER_DIRECTORY/remote-runner.sh" apply stage "$work_directory/bundle.tar.gz" "$SOURCE_COMMIT" test-runner none

probe_value="$(docker exec "$CONTAINER_NAME" psql -X -U supabase_admin -d postgres -Atc 'SELECT value FROM public.hetzner_migration_runner_probe WHERE id = 1')"
[[ "$probe_value" == applied ]]

ledger_hash="$(docker exec "$CONTAINER_NAME" psql -X -U supabase_admin -d postgres -Atc "SELECT sha256 FROM sellton_migrations.applied_migrations WHERE migration_path = '$FIXTURE_RELATIVE_PATH'")"
[[ "$ledger_hash" == "$fixture_hash" ]]
find "$work_directory/runtime/migrations-applied/automation" -type f -path "*/files/$FIXTURE_RELATIVE_PATH" | grep -q .

checksum_path="$(find "$work_directory/backups" -maxdepth 1 -type f -name 'postgres-before-*.dump.sha256' -print -quit)"
[[ -n "$checksum_path" ]]
(
  cd "$work_directory/backups"
  sha256sum -c "$(basename "$checksum_path")" >/dev/null
)

plan_output="$(env "${runner_environment[@]}" "$RUNNER_DIRECTORY/remote-runner.sh" plan stage "$work_directory/bundle.tar.gz" "$SOURCE_COMMIT" test-runner none)"
grep -Fq "APPLIED $FIXTURE_RELATIVE_PATH" <<< "$plan_output"

embedded_relative_path="operations/hetzner-migrations/tests/fixtures/002-embedded-transaction.sql"
mkdir -p "$work_directory/embedded/files/$(dirname "$embedded_relative_path")"
cp "$TEST_DIRECTORY/fixtures/002-embedded-transaction.sql" "$work_directory/embedded/files/$embedded_relative_path"
embedded_hash="$(sha256sum "$TEST_DIRECTORY/fixtures/002-embedded-transaction.sql" | awk '{print $1}')"
printf '%s\t%s\n' "$embedded_relative_path" "$embedded_hash" > "$work_directory/embedded/manifest.tsv"
tar -C "$work_directory/embedded" -czf "$work_directory/embedded.tar.gz" manifest.tsv files

set +e
embedded_output="$(env "${runner_environment[@]}" "$RUNNER_DIRECTORY/remote-runner.sh" plan stage "$work_directory/embedded.tar.gz" "$SOURCE_COMMIT" test-runner none 2>&1)"
embedded_status=$?
set -e
[[ $embedded_status -ne 0 ]]
grep -Fq 'contains transaction control' <<< "$embedded_output"

rollback_relative_path="operations/hetzner-migrations/tests/fixtures/003-rollback-probe.sql"
mkdir -p "$work_directory/rollback/files/$(dirname "$rollback_relative_path")"
cp "$TEST_DIRECTORY/fixtures/003-rollback-probe.sql" "$work_directory/rollback/files/$rollback_relative_path"
rollback_hash="$(sha256sum "$TEST_DIRECTORY/fixtures/003-rollback-probe.sql" | awk '{print $1}')"
printf '%s\t%s\n' "$rollback_relative_path" "$rollback_hash" > "$work_directory/rollback/manifest.tsv"
tar -C "$work_directory/rollback" -czf "$work_directory/rollback.tar.gz" manifest.tsv files

set +e
env "${runner_environment[@]}" "$RUNNER_DIRECTORY/remote-runner.sh" apply stage "$work_directory/rollback.tar.gz" "$SOURCE_COMMIT" test-runner none >/dev/null 2>&1
rollback_status=$?
set -e
[[ $rollback_status -ne 0 ]]

rollback_table="$(docker exec "$CONTAINER_NAME" psql -X -U supabase_admin -d postgres -Atc "SELECT to_regclass('public.hetzner_migration_runner_rollback_probe')")"
[[ -z "$rollback_table" ]]
rollback_ledger_count="$(docker exec "$CONTAINER_NAME" psql -X -U supabase_admin -d postgres -Atc "SELECT count(*) FROM sellton_migrations.applied_migrations WHERE migration_path = '$rollback_relative_path'")"
[[ "$rollback_ledger_count" == 0 ]]

printf 'Hetzner PostgreSQL remote runner tests passed\n'
