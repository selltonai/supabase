#!/usr/bin/env bash
set -Eeuo pipefail

echo "=== PostgreSQL: cloud -> Hetzner ==="
/opt/sellton/live-sync/postgres/postgres-sync-status.sh

echo "=== Storage: cloud -> Hetzner ==="
/opt/sellton/live-sync/storage/storage-sync-status.sh
systemctl list-timers --all sellton-storage-live-sync.timer --no-pager

echo "=== MongoDB: Atlas -> Hetzner ==="
systemctl status sellton-mongodb-live-mirror.service --no-pager -l || true
cd /opt/sellton/gmail-api-prod
node scripts/mongodb-live-mirror.js --status

echo "=== Inactive destination applications ==="
printf 'gmail_api|'
systemctl is-active sellton-gmail-api-prod.service || true
docker ps --format '{{.Names}}|{{.Status}}' | grep -E '^(supabase-db|sellton-mongodb-prod|sellton-mongodb-prod-2|sellton-mongodb-prod-3)\|' || true

echo "=== Capacity ==="
df -h / | tail -n 1
free -h | sed -n '1,2p'
