#!/usr/bin/env bash
set -Eeuo pipefail

STATUS="/opt/sellton/live-sync/storage/status.json"
TARGET_ROOT="/opt/sellton/supabase/volumes/storage/stub/stub"

echo "storage_sync_status"
if [[ -r "$STATUS" ]]; then
  cat "$STATUS"
else
  echo "status unavailable"
fi

echo "storage_target_files"
find "$TARGET_ROOT" -type f ! -name '*.partial-*' -printf '%s\n' 2>/dev/null | awk '{count += 1; bytes += $1} END {print count "|" bytes}'

