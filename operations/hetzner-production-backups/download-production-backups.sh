#!/usr/bin/env bash
set -Eeuo pipefail

umask 077

SSH_HOST="${HETZNER_SSH_HOST:-46.224.151.84}"
SSH_USER="${HETZNER_SSH_USER:-root}"
SSH_KEY="${HETZNER_SSH_PRIVATE_KEY_PATH:-${HOME}/.ssh/hetzner-api}"
OUTPUT_DIRECTORY=""
CREATE_BACKUPS=true
WRITERS_STOPPED=false

usage() {
  cat <<'EOF'
Usage:
  download-production-backups.sh [options]

Options:
  --output-dir PATH     Download directory. Defaults to ./sellton-production-backup-<UTC timestamp>.
  --download-only       Download the latest server bundles without creating new ones.
  --writers-stopped     Record that all production writers were stopped for the new backups.
  --host HOST           Hetzner SSH host.
  --user USER           Hetzner SSH user.
  --ssh-key PATH        SSH private key path.
  -h, --help            Show this help.
EOF
}

require_option_value() {
  local option_name="$1"
  local option_value="${2:-}"
  if [[ -z "$option_value" || "$option_value" == --* ]]; then
    echo "missing value for ${option_name}" >&2
    exit 2
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      require_option_value "$1" "${2:-}"
      OUTPUT_DIRECTORY="${2:-}"
      shift 2
      ;;
    --download-only)
      CREATE_BACKUPS=false
      shift
      ;;
    --writers-stopped)
      WRITERS_STOPPED=true
      shift
      ;;
    --host)
      require_option_value "$1" "${2:-}"
      SSH_HOST="${2:-}"
      shift 2
      ;;
    --user)
      require_option_value "$1" "${2:-}"
      SSH_USER="${2:-}"
      shift 2
      ;;
    --ssh-key)
      require_option_value "$1" "${2:-}"
      SSH_KEY="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ "$CREATE_BACKUPS" == "false" && "$WRITERS_STOPPED" == "true" ]]; then
  echo "--writers-stopped cannot be combined with --download-only" >&2
  exit 2
fi

if [[ ! -r "$SSH_KEY" ]]; then
  echo "SSH private key is not readable: $SSH_KEY" >&2
  exit 1
fi

if [[ -z "$OUTPUT_DIRECTORY" ]]; then
  OUTPUT_DIRECTORY="${PWD}/sellton-production-backup-$(date -u +%Y%m%d-%H%M%S)"
fi
install -d -m 700 "$OUTPUT_DIRECTORY"

ssh_options=(-F /dev/null -i "$SSH_KEY" -o BatchMode=yes -o StrictHostKeyChecking=yes)
remote="${SSH_USER}@${SSH_HOST}"
backup_mode=()
if [[ "$WRITERS_STOPPED" == "true" ]]; then
  backup_mode=(--writers-stopped)
fi

if [[ "$CREATE_BACKUPS" == "true" ]]; then
  echo "creating Supabase production bundle on Hetzner"
  ssh "${ssh_options[@]}" "$remote" /opt/sellton/backup-tools/create-supabase-backup.sh "${backup_mode[@]}"

  echo "creating MongoDB production bundle on Hetzner"
  ssh "${ssh_options[@]}" "$remote" /opt/sellton/backup-tools/create-mongodb-backup.sh "${backup_mode[@]}"
fi

supabase_archive="$(ssh "${ssh_options[@]}" "$remote" readlink -f /opt/sellton/backups/downloadable/supabase-production-latest.tar.gz)"
mongodb_archive="$(ssh "${ssh_options[@]}" "$remote" readlink -f /opt/sellton/backups/downloadable/mongodb-production-latest.tar.gz)"

if [[ "$supabase_archive" != /opt/sellton/backups/downloadable/supabase-production-*.tar.gz ]]; then
  echo "unexpected Supabase archive path: $supabase_archive" >&2
  exit 1
fi
if [[ "$mongodb_archive" != /opt/sellton/backups/downloadable/mongodb-production-*.tar.gz ]]; then
  echo "unexpected MongoDB archive path: $mongodb_archive" >&2
  exit 1
fi

echo "downloading verified production bundles"
scp "${ssh_options[@]}" "${remote}:${supabase_archive}" "${remote}:${supabase_archive}.sha256" "$OUTPUT_DIRECTORY/"
scp "${ssh_options[@]}" "${remote}:${mongodb_archive}" "${remote}:${mongodb_archive}.sha256" "$OUTPUT_DIRECTORY/"

(
  cd "$OUTPUT_DIRECTORY"
  sha256sum --check "$(basename "${supabase_archive}.sha256")"
  sha256sum --check "$(basename "${mongodb_archive}.sha256")"
)

cat > "${OUTPUT_DIRECTORY}/README.txt" <<EOF
Sellton Hetzner production backups
Downloaded at: $(date -u +%FT%TZ)
Source: ${remote}
Supabase: $(basename "$supabase_archive")
MongoDB: $(basename "$mongodb_archive")
Writers stopped: ${WRITERS_STOPPED}

These archives contain production customer data. Store them securely.
They intentionally exclude active .env files, API keys, and the MongoDB replica-set keyfile.
EOF
chmod 600 "${OUTPUT_DIRECTORY}/README.txt"

echo "backups-downloaded: $OUTPUT_DIRECTORY"
du -h "${OUTPUT_DIRECTORY}/$(basename "$supabase_archive")" "${OUTPUT_DIRECTORY}/$(basename "$mongodb_archive")"
