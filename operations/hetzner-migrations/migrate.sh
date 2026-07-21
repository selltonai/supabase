#!/usr/bin/env bash

set -Eeuo pipefail
umask 077

usage() {
  cat <<'EOF'
Usage:
  ./operations/hetzner-migrations/migrate.sh status <stage|production>
  ./operations/hetzner-migrations/migrate.sh plan <stage|production> <migration.sql>...
  ./operations/hetzner-migrations/migrate.sh apply <stage|production> <migration.sql>... [--confirm-production]

Environment overrides:
  HETZNER_SSH_HOST        Default: 46.224.151.84
  HETZNER_SSH_USER        Default: root
  HETZNER_SSH_KEY         Default: /home/systempro/.ssh/hetzner-api
  HETZNER_KNOWN_HOSTS     Default: operations/hetzner-migrations/known_hosts
  HETZNER_MIGRATION_ACTOR Audit label; defaults to local user and hostname
  HETZNER_PRODUCTION_BRANCH Default: main
EOF
}

log() {
  printf '[postgres-migrate] %s\n' "$*"
}

fail() {
  log "ERROR: $*" >&2
  exit 1
}

[[ $# -ge 2 ]] || {
  usage >&2
  exit 2
}

readonly ACTION="$1"
readonly TARGET_ENVIRONMENT="$2"
shift 2

case "$ACTION" in
  status|plan|apply) ;;
  *) fail "Unsupported action '$ACTION'; use status, plan, or apply" ;;
esac

case "$TARGET_ENVIRONMENT" in
  stage|production) ;;
  *) fail "Unsupported environment '$TARGET_ENVIRONMENT'; use stage or production" ;;
esac

confirm_production=false
migration_arguments=()
for argument in "$@"; do
  case "$argument" in
    --confirm-production)
      confirm_production=true
      ;;
    --*)
      fail "Unknown option: $argument"
      ;;
    *)
      migration_arguments+=("$argument")
      ;;
  esac
done

if [[ "$ACTION" == status && ${#migration_arguments[@]} -ne 0 ]]; then
  fail "status does not accept migration files"
fi
if [[ "$ACTION" != status && ${#migration_arguments[@]} -eq 0 ]]; then
  fail "$ACTION requires at least one migration file"
fi
if [[ "$ACTION" == apply && "$TARGET_ENVIRONMENT" == production && "$confirm_production" != true ]]; then
  fail "production apply requires --confirm-production"
fi

for required_command in awk cp cut date dirname git mkdir mktemp realpath rm scp sha256sum ssh tar uname; do
  command -v "$required_command" >/dev/null 2>&1 || fail "Required command is unavailable: $required_command"
done

readonly SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "$SCRIPT_DIRECTORY/../.." && pwd)"
readonly REMOTE_RUNNER="$SCRIPT_DIRECTORY/remote-runner.sh"
readonly SSH_HOST="${HETZNER_SSH_HOST:-46.224.151.84}"
readonly SSH_USER="${HETZNER_SSH_USER:-root}"
readonly SSH_KEY="${HETZNER_SSH_KEY:-/home/systempro/.ssh/hetzner-api}"
readonly KNOWN_HOSTS="${HETZNER_KNOWN_HOSTS:-$SCRIPT_DIRECTORY/known_hosts}"
readonly SOURCE_COMMIT="$(git -C "$REPOSITORY_ROOT" rev-parse HEAD)"
readonly CURRENT_BRANCH="$(git -C "$REPOSITORY_ROOT" symbolic-ref --quiet --short HEAD || true)"
readonly PRODUCTION_BRANCH="${HETZNER_PRODUCTION_BRANCH:-main}"
readonly SHORT_COMMIT="${SOURCE_COMMIT:0:12}"
readonly MIGRATION_ACTOR="${HETZNER_MIGRATION_ACTOR:-${USER:-operator}@$(uname -n | cut -d. -f1)}"

[[ -f "$REMOTE_RUNNER" ]] || fail "Remote runner is missing: $REMOTE_RUNNER"
[[ -f "$SSH_KEY" ]] || fail "SSH key is missing: $SSH_KEY"
[[ -f "$KNOWN_HOSTS" ]] || fail "Pinned SSH known_hosts file is missing: $KNOWN_HOSTS"
[[ "$MIGRATION_ACTOR" =~ ^[A-Za-z0-9._@-]+$ ]] || fail "Migration actor contains unsupported characters"

if [[ "$ACTION" == apply && "$TARGET_ENVIRONMENT" == production ]]; then
  [[ "$CURRENT_BRANCH" == "$PRODUCTION_BRANCH" ]] || fail "Production apply requires branch $PRODUCTION_BRANCH; current branch is ${CURRENT_BRANCH:-detached}"
  for runner_source in operations/hetzner-migrations/migrate.sh operations/hetzner-migrations/remote-runner.sh operations/hetzner-migrations/known_hosts; do
    git -C "$REPOSITORY_ROOT" ls-files --error-unmatch "$runner_source" >/dev/null 2>&1 || fail "Production runner source must be committed: $runner_source"
    git -C "$REPOSITORY_ROOT" diff --quiet HEAD -- "$runner_source" || fail "Production runner source differs from HEAD: $runner_source"
  done
fi

work_directory="$(mktemp -d)"
readonly work_directory
readonly bundle_directory="$work_directory/bundle"
readonly manifest_path="$bundle_directory/manifest.tsv"
readonly archive_path="$work_directory/postgres-migrations.tar.gz"

cleanup() {
  rm -rf "$work_directory"
}
trap cleanup EXIT

mkdir -p "$bundle_directory/files"
: > "$manifest_path"

declare -A seen_paths=()
for migration_argument in "${migration_arguments[@]}"; do
  if [[ "$migration_argument" == /* ]]; then
    migration_path="$(realpath -e "$migration_argument")"
  else
    migration_path="$(realpath -e "$REPOSITORY_ROOT/$migration_argument")"
  fi

  [[ "$migration_path" == "$REPOSITORY_ROOT/"* ]] || fail "Migration is outside the repository: $migration_argument"
  [[ "$migration_path" == *.sql ]] || fail "PostgreSQL migration must end in .sql: $migration_argument"

  relative_path="${migration_path#"$REPOSITORY_ROOT/"}"
  [[ "$relative_path" =~ ^[A-Za-z0-9._/-]+$ ]] || fail "Migration path contains unsupported characters: $relative_path"
  [[ -z "${seen_paths[$relative_path]:-}" ]] || fail "Migration listed more than once: $relative_path"
  seen_paths[$relative_path]=1

  migration_hash="$(sha256sum "$migration_path" | awk '{print $1}')"
  if [[ "$ACTION" == apply && "$TARGET_ENVIRONMENT" == production ]]; then
    git -C "$REPOSITORY_ROOT" ls-files --error-unmatch "$relative_path" >/dev/null 2>&1 || fail "Production migration must be committed: $relative_path"
    git -C "$REPOSITORY_ROOT" diff --quiet HEAD -- "$relative_path" || fail "Production migration differs from HEAD: $relative_path"
  fi
  mkdir -p "$bundle_directory/files/$(dirname "$relative_path")"
  cp "$migration_path" "$bundle_directory/files/$relative_path"
  printf '%s\t%s\n' "$relative_path" "$migration_hash" >> "$manifest_path"
done

tar -C "$bundle_directory" -czf "$archive_path" manifest.tsv files

readonly remote_token="${TARGET_ENVIRONMENT}-${SHORT_COMMIT}-$(date -u +%Y%m%dT%H%M%SZ)-$$"
readonly remote_archive="/tmp/sellton-postgres-migrations-$remote_token.tar.gz"
readonly remote_runner="/tmp/sellton-postgres-migrate-$remote_token.sh"
readonly -a ssh_options=(-F /dev/null -i "$SSH_KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o "UserKnownHostsFile=$KNOWN_HOSTS")

log "Uploading verified migration bundle: environment=$TARGET_ENVIRONMENT action=$ACTION files=${#migration_arguments[@]} commit=$SOURCE_COMMIT"
scp "${ssh_options[@]}" "$archive_path" "$SSH_USER@$SSH_HOST:$remote_archive"
scp "${ssh_options[@]}" "$REMOTE_RUNNER" "$SSH_USER@$SSH_HOST:$remote_runner"

confirmation="none"
if [[ "$confirm_production" == true ]]; then
  confirmation="production"
fi

remote_command=(bash "$remote_runner" "$ACTION" "$TARGET_ENVIRONMENT" "$remote_archive" "$SOURCE_COMMIT" "$MIGRATION_ACTOR" "$confirmation")
if [[ "$SSH_USER" != root ]]; then
  remote_command=(sudo -n "${remote_command[@]}")
fi
printf -v quoted_remote_command '%q ' "${remote_command[@]}"

ssh "${ssh_options[@]}" "$SSH_USER@$SSH_HOST" "$quoted_remote_command"
