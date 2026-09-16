#!/usr/bin/env bash
# Creates a disposable PostgreSQL container; never connects to an existing DB.
set -euo pipefail
cd "$(dirname "$0")/.."
container="sellton-billing-contract-$$"
trap 'docker rm -f "$container" >/dev/null 2>&1 || true' EXIT
docker run --rm -d --name "$container" -e POSTGRES_HOST_AUTH_METHOD=trust postgres:15-alpine >/dev/null
for attempt in {1..30}; do
  if docker exec "$container" pg_isready -U postgres >/dev/null 2>&1; then break; fi
  sleep 1
done
for sql in \
  tests/fixtures/billing-link-recovery-bootstrap.sql \
  migrations/release_1.1.0/243_billing.sql \
  migrations/release_1.2.0/326_speed-up-usage-billing-pages.sql \
  migrations/release_1.3.0/345_usage-analytics-projection.sql \
  migrations/release_1.3.0/370_billing-invoice-link-recovery.sql \
  migrations/release_1.3.0/370_billing-invoice-link-recovery.sql \
  tests/usage-analytics-projection.contract.sql \
  tests/billing-invoice-link-recovery.contract.sql; do
  echo "Checking $sql"
  docker exec -i "$container" psql -X -q -U postgres -v ON_ERROR_STOP=1 < "$sql"
done
docker exec -i "$container" psql -X -q -U postgres -v ON_ERROR_STOP=1 < tests/billing-invoice-link-repair-fixture.sql
for attempt in 1 2; do
  docker exec -i "$container" psql -X -q -U postgres -v ON_ERROR_STOP=1 -v org_id=repair-contract-a -v invoice_id=cccccccc-cccc-4ccc-8ccc-cccccccccccc < operations/billing-invoice-link-recovery/repair-verified-invoice.sql
done
if docker exec -i "$container" psql -X -q -U postgres -v ON_ERROR_STOP=1 -v org_id=repair-contract-a -v invoice_id=dddddddd-dddd-4ddd-8ddd-dddddddddddd < operations/billing-invoice-link-recovery/repair-verified-invoice.sql; then
  echo 'ERROR: mismatched legacy invoice was not rejected' >&2
  exit 1
fi
docker exec -i "$container" psql -X -q -U postgres -v ON_ERROR_STOP=1 < tests/billing-invoice-link-repair-assert.sql
echo 'Billing linkage, analytics, and legacy repair contracts passed.'
