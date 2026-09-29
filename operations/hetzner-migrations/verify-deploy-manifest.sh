#!/usr/bin/env bash
set -euo pipefail

manifest="${1:-operations/hetzner-migrations/deploy-manifest.txt}"
mapfile -t entries < <(sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$manifest")

declare -A managed_directories=()
declare -A manifest_hashes=()
for entry in "${entries[@]}"; do
  [[ -f "$entry" ]] || {
    printf 'Manifest migration does not exist: %s\n' "$entry" >&2
    exit 1
  }
  checksum="$(sha256sum "$entry")"
  manifest_hashes["${checksum%% *}"]="$entry"
  directory="${entry%/*}"
  number="${entry##*/}"
  number="${number%%_*}"
  if [[ "$number" =~ ^[0-9]+$ ]]; then
    current="${managed_directories[$directory]:-}"
    if [[ -z "$current" || "$number" -lt "$current" ]]; then
      managed_directories[$directory]="$number"
    fi
  fi
done

missing=()
for directory in "${!managed_directories[@]}"; do
  managed_from="${managed_directories[$directory]}"
  while IFS= read -r migration; do
    filename="${migration##*/}"
    number="${filename%%_*}"
    [[ "$number" =~ ^[0-9]+$ && "$number" -ge "$managed_from" ]] || continue
    if ! grep -Fxq "$migration" "$manifest"; then
      # Branches can store the same already-deployed SQL under different paths.
      # The deployment runner still uses full path + hash as its identity; do
      # not add the alias to this branch's manifest and replay its SQL.
      checksum="$(sha256sum "$migration")"
      if [[ -n "${manifest_hashes[${checksum%% *}]:-}" ]]; then
        continue
      fi
      missing+=("$migration")
    fi
  done < <(find "$directory" -maxdepth 1 -type f -name '*.sql' -print | sort -V)
done

if (( ${#missing[@]} > 0 )); then
  printf 'Managed migration missing from %s:\n' "$manifest" >&2
  printf '  %s\n' "${missing[@]}" >&2
  exit 1
fi

printf 'Manifest completeness verified for %d managed migration(s).\n' "${#entries[@]}"
