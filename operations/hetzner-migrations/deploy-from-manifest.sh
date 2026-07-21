#!/usr/bin/env bash

set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./operations/hetzner-migrations/deploy-from-manifest.sh <stage|production>

Environment overrides:
  HETZNER_MIGRATION_MANIFEST  Default: operations/hetzner-migrations/deploy-manifest.txt
  HETZNER_MIGRATION_RUNNER    Default: operations/hetzner-migrations/migrate.sh
EOF
}

log() {
  printf '[postgres-deploy] %s\n' "$*"
}

fail() {
  log "ERROR: $*" >&2
  exit 1
}

[[ $# -eq 1 ]] || {
  usage >&2
  exit 2
}

readonly TARGET_ENVIRONMENT="$1"
case "$TARGET_ENVIRONMENT" in
  stage|production) ;;
  *) fail "Unsupported environment '$TARGET_ENVIRONMENT'; use stage or production" ;;
esac

readonly SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "$SCRIPT_DIRECTORY/../.." && pwd)"
readonly MANIFEST_PATH="${HETZNER_MIGRATION_MANIFEST:-$SCRIPT_DIRECTORY/deploy-manifest.txt}"
readonly MIGRATION_RUNNER="${HETZNER_MIGRATION_RUNNER:-$SCRIPT_DIRECTORY/migrate.sh}"

[[ -f "$MANIFEST_PATH" ]] || fail "Deployment manifest is missing: $MANIFEST_PATH"
[[ -x "$MIGRATION_RUNNER" ]] || fail "Migration runner is not executable: $MIGRATION_RUNNER"

declare -a migration_paths=()
declare -A seen_paths=()
line_number=0
while IFS= read -r manifest_line || [[ -n "$manifest_line" ]]; do
  line_number=$((line_number + 1))
  manifest_line="${manifest_line%$'\r'}"

  if [[ -z "$manifest_line" || "$manifest_line" =~ ^[[:space:]]*# ]]; then
    continue
  fi
  [[ "$manifest_line" =~ ^migrations/[A-Za-z0-9._/-]+\.sql$ ]] || fail "Invalid migration path at $MANIFEST_PATH:$line_number"
  [[ -z "${seen_paths[$manifest_line]:-}" ]] || fail "Duplicate migration in manifest: $manifest_line"
  [[ -f "$REPOSITORY_ROOT/$manifest_line" ]] || fail "Manifest migration does not exist: $manifest_line"
  git -C "$REPOSITORY_ROOT" ls-files --error-unmatch "$manifest_line" >/dev/null 2>&1 || fail "Manifest migration is not committed: $manifest_line"

  seen_paths[$manifest_line]=1
  migration_paths+=("$manifest_line")
done < "$MANIFEST_PATH"

[[ ${#migration_paths[@]} -gt 0 ]] || fail "Deployment manifest contains no migrations"

log "Planning ${#migration_paths[@]} migration(s) for $TARGET_ENVIRONMENT"
"$MIGRATION_RUNNER" plan "$TARGET_ENVIRONMENT" "${migration_paths[@]}"

apply_arguments=(apply "$TARGET_ENVIRONMENT" "${migration_paths[@]}")
if [[ "$TARGET_ENVIRONMENT" == production ]]; then
  apply_arguments+=(--confirm-production)
fi

log "Applying ${#migration_paths[@]} migration(s) to $TARGET_ENVIRONMENT"
"$MIGRATION_RUNNER" "${apply_arguments[@]}"

log "Verifying migration ledger for $TARGET_ENVIRONMENT"
"$MIGRATION_RUNNER" plan "$TARGET_ENVIRONMENT" "${migration_paths[@]}"
"$MIGRATION_RUNNER" status "$TARGET_ENVIRONMENT"
