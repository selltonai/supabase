#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly VERIFY_SCRIPT="$SCRIPT_DIRECTORY/../verify-deploy-manifest.sh"
work_directory="$(mktemp -d)"
trap 'rm -rf "$work_directory"' EXIT

mkdir -p "$work_directory/migrations/release_9.9.9" "$work_directory/operations"
printf 'SELECT 1;\n' > "$work_directory/migrations/release_9.9.9/901_first.sql"
printf 'SELECT 2;\n' > "$work_directory/migrations/release_9.9.9/902_second.sql"
printf '%s\n' 'migrations/release_9.9.9/901_first.sql' > "$work_directory/operations/manifest.txt"

if (cd "$work_directory" && "$VERIFY_SCRIPT" operations/manifest.txt >/dev/null 2>&1); then
  echo "Verifier accepted a managed migration missing from the manifest" >&2
  exit 1
fi

printf '%s\n' 'migrations/release_9.9.9/902_second.sql' >> "$work_directory/operations/manifest.txt"
(cd "$work_directory" && "$VERIFY_SCRIPT" operations/manifest.txt >/dev/null)

# Identical SQL already listed under another branch path is covered without
# asking the deployment runner to apply that SQL a second time.
mkdir -p "$work_directory/migrations/next-release"
cp "$work_directory/migrations/release_9.9.9/902_second.sql" "$work_directory/migrations/next-release/920_second.sql"
printf '%s\n' 'migrations/release_9.9.9/901_first.sql' 'migrations/next-release/920_second.sql' > "$work_directory/operations/manifest.txt"
(cd "$work_directory" && "$VERIFY_SCRIPT" operations/manifest.txt >/dev/null)

printf 'SELECT 3;\n' > "$work_directory/migrations/next-release/920_second.sql"
if (cd "$work_directory" && "$VERIFY_SCRIPT" operations/manifest.txt >/dev/null 2>&1); then
  echo "Verifier accepted different SQL as an equivalent migration" >&2
  exit 1
fi

echo "Deploy manifest completeness tests passed"
