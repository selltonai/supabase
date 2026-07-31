#!/usr/bin/env bash

set -Eeuo pipefail

readonly SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "$SCRIPT_DIRECTORY/../../.." && pwd)"
readonly DEPLOY_SCRIPT="$REPOSITORY_ROOT/operations/hetzner-migrations/deploy-from-manifest.sh"
readonly TEST_MIGRATION="migrations/release_1.3.0/344_email-sequence-audience-mode.sql"

work_directory="$(mktemp -d)"
cleanup() {
  rm -rf "$work_directory"
}
trap cleanup EXIT

fake_runner="$work_directory/fake-migrate.sh"
runner_log="$work_directory/runner.log"
manifest_path="$work_directory/deploy-manifest.txt"

cat > "$fake_runner" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_RUNNER_LOG"
EOF
chmod 700 "$fake_runner"

cat > "$manifest_path" <<EOF
# Comments and blank lines are ignored.

$TEST_MIGRATION
EOF

FAKE_RUNNER_LOG="$runner_log" HETZNER_MIGRATION_MANIFEST="$manifest_path" HETZNER_MIGRATION_RUNNER="$fake_runner" "$DEPLOY_SCRIPT" stage

expected_stage_calls="$(cat <<EOF
plan stage $TEST_MIGRATION
apply stage $TEST_MIGRATION
plan stage $TEST_MIGRATION
status stage
EOF
)"
[[ "$(cat "$runner_log")" == "$expected_stage_calls" ]]

: > "$runner_log"
FAKE_RUNNER_LOG="$runner_log" HETZNER_MIGRATION_MANIFEST="$manifest_path" HETZNER_MIGRATION_RUNNER="$fake_runner" "$DEPLOY_SCRIPT" production
grep -Fxq "apply production $TEST_MIGRATION --confirm-production" "$runner_log"

printf '%s\n%s\n' "$TEST_MIGRATION" "$TEST_MIGRATION" > "$manifest_path"
if FAKE_RUNNER_LOG="$runner_log" HETZNER_MIGRATION_MANIFEST="$manifest_path" HETZNER_MIGRATION_RUNNER="$fake_runner" "$DEPLOY_SCRIPT" stage >/dev/null 2>&1; then
  printf 'Expected duplicate manifest migration to fail\n' >&2
  exit 1
fi

printf 'deploy-from-manifest tests passed\n'
