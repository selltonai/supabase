#!/usr/bin/env bash
# KAN-322 FR-A11i: time dashboard_outcomes_v1 on a synthetic large workspace. Disposable local Postgres only.
set -euo pipefail
export LC_ALL="${LC_ALL:-C}"
cd "$(dirname "$0")/.."
PG_BIN="${PG_BIN:-$(dirname "$(command -v postgres || echo /opt/homebrew/opt/postgresql@15/bin/postgres)")}"
data="$(mktemp -d)"; sock="$(mktemp -d /tmp/pgs.XXXX)"; port="${PG_TEST_PORT:-55442}"
trap '"$PG_BIN/pg_ctl" -D "$data" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$data" "$sock"' EXIT
"$PG_BIN/initdb" -D "$data" -U postgres -A trust >/dev/null
"$PG_BIN/pg_ctl" -D "$data" -o "-p $port -k $sock -c listen_addresses=''" -l "$data/server.log" -w start >/dev/null
q() { "$PG_BIN/psql" -X -q -h "$sock" -p "$port" -U postgres -v ON_ERROR_STOP=1 "$@"; }
q -f tests/fixtures/dashboard-outcomes-bootstrap.sql
q -f migrations/next-release/406_dashboard-outcomes-new-people-meetings-deals.sql
q <<'SQL'
-- 300 plays (a third LinkedIn), 60k company links, 150k people at those companies, 60k enrolments,
-- 8k deals with 40k stage events, plus a second workspace of the same size that must not be read.
INSERT INTO campaigns SELECT ('00000000-0000-0000-0001-' || lpad(g::text, 12, '0'))::uuid, CASE WHEN g <= 300 THEN 'big' ELSE 'other' END,
  'u' || (g % 20), CASE g % 3 WHEN 0 THEN 'linkedin' WHEN 1 THEN 'email' ELSE NULL END FROM generate_series(1, 600) g;
INSERT INTO contacts SELECT ('00000000-0000-0000-0003-' || lpad(g::text, 12, '0'))::uuid, CASE WHEN g <= 150000 THEN 'big' ELSE 'other' END,
  timestamptz '2025-01-01' + (g % 600) * interval '1 day' FROM generate_series(1, 300000) g;
INSERT INTO campaign_companies (campaign_id, company_id, organization_id, created_at, blocked_by_icp)
  SELECT ('00000000-0000-0000-0001-' || lpad((((g - 1) % 300) + 1 + CASE WHEN g > 60000 THEN 300 ELSE 0 END)::text, 12, '0'))::uuid,
         ('00000000-0000-0000-0002-' || lpad(g::text, 12, '0'))::uuid, CASE WHEN g <= 60000 THEN 'big' ELSE 'other' END,
         timestamptz '2025-01-01' + (g % 650) * interval '1 day', g % 17 = 0 FROM generate_series(1, 120000) g;
INSERT INTO company_contacts (company_id, contact_id, organization_id)
  SELECT ('00000000-0000-0000-0002-' || lpad((((g - 1) % 60000) + 1 + CASE WHEN g > 150000 THEN 60000 ELSE 0 END)::text, 12, '0'))::uuid,
         ('00000000-0000-0000-0003-' || lpad(g::text, 12, '0'))::uuid, CASE WHEN g <= 150000 THEN 'big' ELSE 'other' END FROM generate_series(1, 300000) g;
INSERT INTO campaign_contacts (campaign_id, contact_id, organization_id, created_at)
  SELECT ('00000000-0000-0000-0001-' || lpad((((g - 1) % 100) * 3 + 3)::text, 12, '0'))::uuid,
         ('00000000-0000-0000-0003-' || lpad(g::text, 12, '0'))::uuid, 'big', timestamptz '2025-01-01' + (g % 640) * interval '1 day'
  FROM generate_series(1, 60000) g;
INSERT INTO deals SELECT ('00000000-0000-0000-0004-' || lpad(g::text, 12, '0'))::uuid, CASE WHEN g <= 8000 THEN 'big' ELSE 'other' END,
  ('00000000-0000-0000-0003-' || lpad(g::text, 12, '0'))::uuid, NULL, 'u' || (g % 20),
  CASE WHEN g % 5 = 0 THEN 'WON' ELSE 'MEETING_BOOKED' END, g, 'EUR', CASE WHEN g % 5 = 0 THEN timestamptz '2026-09-01' + (g % 40) * interval '1 day' END
  FROM generate_series(1, 16000) g;
INSERT INTO deal_activities (deal_id, organization_id, activity_type, metadata, created_at)
  SELECT ('00000000-0000-0000-0004-' || lpad((((g - 1) % 16000) + 1)::text, 12, '0'))::uuid, CASE WHEN ((g - 1) % 16000) < 8000 THEN 'big' ELSE 'other' END,
         'stage_change', jsonb_build_object('to', CASE g % 4 WHEN 0 THEN 'MEETING_BOOKED' WHEN 1 THEN 'LEAD' WHEN 2 THEN 'PRESENTATION' ELSE 'NOTE' END),
         timestamptz '2025-06-01' + (g % 500) * interval '1 day' FROM generate_series(1, 80000) g;
ANALYZE;
SQL
for scope in "NULL" "'u3'"; do
  echo "== scope $scope"
  q -c "EXPLAIN (ANALYZE, BUFFERS OFF, TIMING ON, SUMMARY ON) SELECT * FROM dashboard_outcomes_v1('big', '2026-09-20', '2026-10-20', $scope)" | grep -E "Execution Time|Planning Time"
  q -tAc "SELECT * FROM dashboard_outcomes_v1('big', '2026-09-20', '2026-10-20', $scope)"
done
