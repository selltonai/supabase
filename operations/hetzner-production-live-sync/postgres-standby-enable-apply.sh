#!/usr/bin/env bash
set -Eeuo pipefail

container_name="${1:-sellton-postgres-standby}"
catalog_path="/work/schema/source.db"

if ! docker ps --format '{{.Names}}' | grep -qx "$container_name"; then
  echo "PostgreSQL standby container is not running: $container_name" >&2
  exit 1
fi

# pgcopydb v0.17 loses active filters when its sentinel CLI reopens this
# catalog. The pinned version stores the apply gate in this single row.
docker exec "$container_name" sqlite3 -cmd '.timeout 5000' "$catalog_path" \
  "BEGIN IMMEDIATE; UPDATE sentinel SET apply=1 WHERE id=1; COMMIT;" >/dev/null

sentinel_apply="$(docker exec "$container_name" sqlite3 "$catalog_path" "SELECT CASE WHEN apply=1 THEN 'enabled' ELSE 'disabled' END FROM sentinel WHERE id=1;")"
if [[ "$sentinel_apply" != "enabled" ]]; then
  echo "PostgreSQL standby apply gate was not enabled: ${sentinel_apply:-missing}" >&2
  exit 1
fi

echo "PostgreSQL Hetzner-to-cloud standby apply enabled"
