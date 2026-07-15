#!/usr/bin/env bash
set -Eeuo pipefail

MODE="${1:-status}"
STATUS="/opt/sellton/live-sync/storage-standby/status.json"

timer_active="$(systemctl is-active sellton-storage-standby.timer 2>/dev/null || true)"
timer_enabled="$(systemctl is-enabled sellton-storage-standby.timer 2>/dev/null || true)"
echo "storage_standby_timer_active=$timer_active"
echo "storage_standby_timer_enabled=$timer_enabled"

if [[ -r "$STATUS" ]]; then
  cat "$STATUS"
else
  echo "storage standby status unavailable"
fi

if [[ "$MODE" == "--check" ]]; then
  if [[ "$timer_active" != "active" || "$timer_enabled" != "enabled" || ! -r "$STATUS" ]]; then
    echo "Storage standby timer or status is not ready" >&2
    exit 1
  fi
  status_values="$(STATUS_FILE="$STATUS" node -e '
    const status=require(process.env.STATUS_FILE);
    const completedAt=Date.parse(status.completed_at);
    const ageSeconds=Number.isFinite(completedAt) ? Math.floor((Date.now()-completedAt)/1000) : -1;
    process.stdout.write(`${status.manifest_objects}|${status.failures?.length || 0}|${ageSeconds}`);
  ')"
  IFS='|' read -r manifest_objects failure_count status_age_seconds <<< "$status_values"
  if [[ -z "$manifest_objects" || "$failure_count" != "0" || "$status_age_seconds" -lt 0 || "$status_age_seconds" -gt 300 ]]; then
    echo "Storage standby is unhealthy: objects=${manifest_objects:-missing} failures=${failure_count:-missing} status_age_seconds=${status_age_seconds:-missing}" >&2
    exit 1
  fi
elif [[ "$MODE" != "status" ]]; then
  echo "usage: $0 [--check]" >&2
  exit 2
fi
