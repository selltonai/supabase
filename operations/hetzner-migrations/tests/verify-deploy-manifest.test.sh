#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly VERIFY_SCRIPT="$SCRIPT_DIRECTORY/../verify-deploy-manifest.sh"
work_directory="$(mktemp -d)"
trap 'rm -rf "$work_directory"' EXIT

mkdir -p "$work_directory/migrations/release_9.9.9" "$work_directory/operations"
touch "$work_directory/migrations/release_9.9.9/901_first.sql"
touch "$work_directory/migrations/release_9.9.9/902_second.sql"
printf '%s\n' 'migrations/release_9.9.9/901_first.sql' > "$work_directory/operations/manifest.txt"

if (cd "$work_directory" && "$VERIFY_SCRIPT" operations/manifest.txt >/dev/null 2>&1); then
  echo "Verifier accepted a managed migration missing from the manifest" >&2
  exit 1
fi

printf '%s\n' 'migrations/release_9.9.9/902_second.sql' >> "$work_directory/operations/manifest.txt"
(cd "$work_directory" && "$VERIFY_SCRIPT" operations/manifest.txt >/dev/null)

echo "Deploy manifest completeness tests passed"
