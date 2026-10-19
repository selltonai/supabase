#!/usr/bin/env bash
# A disposable database only; never connects to any deployed environment.
set -euo pipefail
cd "$(dirname "$0")/.."
container="sellton-call-contract-$$"
trap 'docker rm -f "$container" >/dev/null 2>&1 || true' EXIT
docker run --rm -d --name "$container" -e POSTGRES_HOST_AUTH_METHOD=trust postgres:15-alpine >/dev/null
for attempt in {1..30}; do
  if docker exec "$container" pg_isready -U postgres >/dev/null 2>&1; then break; fi
  sleep 1
done
for sql in tests/fixtures/crm-call-bootstrap.sql migrations/release_1.3.0/352_crm-deal-task-workflows.sql migrations/next-release/375_crm-call-task-type.sql migrations/next-release/376_crm-call-task-workflows.sql migrations/next-release/375_crm-call-task-type.sql migrations/next-release/376_crm-call-task-workflows.sql migrations/next-release/377_crm-call-task-status-guard.sql migrations/next-release/377_crm-call-task-status-guard.sql tests/crm-call-tasks-contract.sql; do
  echo "Checking $sql"
  docker exec -i "$container" psql -X -q -U postgres -v ON_ERROR_STOP=1 < "$sql"
done
echo 'CRM call task contracts passed.'
