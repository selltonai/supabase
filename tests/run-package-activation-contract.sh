#!/usr/bin/env bash
# Migrations 453 and 454: a disposable local Postgres only; never connects to any deployed environment.
# Applies the bootstrap and the real tables the functions touch (307, 422, 427, 428, 446), then 453 and 454 twice
# each (they must be re-runnable), checks the contract in one session, then in two concurrent sessions (S8: one code
# redeemed at once by two workspaces; S3: one Checkout session activated at once by two webhooks), then the
# rollbacks (454, then 453) against the schema as it was before 453, then 453 and 454 once more.
# On Windows (Git Bash) the cluster listens on 127.0.0.1 only, as Unix socket paths there are too long; elsewhere on
# a socket only. PG_BIN, PG_TEST_PORT and PG_TEST_DIR (where the throwaway cluster lives) may be set.
set -euo pipefail
export LC_ALL="${LC_ALL:-C}"
cd "$(dirname "$0")/.."
PG_BIN="${PG_BIN:-$(dirname "$(command -v postgres || echo /opt/homebrew/opt/postgresql@15/bin/postgres)")}"
port="${PG_TEST_PORT:-55454}"
base="${PG_TEST_DIR:-${TMPDIR:-/tmp}}"
data="$(mktemp -d "$base/pgd.XXXX")"
if command -v cygpath >/dev/null 2>&1; then
  host=127.0.0.1; sock=""
  server_opts="-p $port -c listen_addresses=127.0.0.1"
else
  sock="$(mktemp -d /tmp/pgs.XXXX)"; host="$sock"
  server_opts="-p $port -k $sock -c listen_addresses=''"
fi
trap '"$PG_BIN/pg_ctl" -D "$data" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$data" ${sock:+"$sock"}' EXIT
"$PG_BIN/initdb" -D "$data" -U postgres -A trust >/dev/null
"$PG_BIN/pg_ctl" -D "$data" -o "$server_opts" -l "$data/server.log" -w start >/dev/null || { cat "$data/server.log"; exit 1; }
psql_() { "$PG_BIN/psql" -X -q -h "$host" -p "$port" -U postgres -v ON_ERROR_STOP=1 "$@"; }
run() {
  echo "Checking $1"
  # One transaction per file, as the migration runner applies them (SET LOCAL needs it).
  psql_ --single-transaction -f "$1"
}

run tests/fixtures/package-activation-bootstrap.sql
run migrations/release_1.2.0/307_create_activation_fees.sql
run migrations/next-release/422_backoffice-cs-agent-core.sql
run migrations/next-release/427_backoffice-cs-agent-commercial.sql
run migrations/next-release/428_backoffice-cs-agent-deletion.sql
run migrations/next-release/446_billing-v2-cycle-charges.sql
psql_ -c 'CREATE TABLE contract_fixture.schema_before AS SELECT * FROM contract_fixture.schema_items'
run migrations/next-release/453_billing-packages-and-codes.sql
run migrations/next-release/453_billing-packages-and-codes.sql
run migrations/next-release/454_package-activation-functions.sql
run migrations/next-release/454_package-activation-functions.sql
run tests/package-activation-contract.sql

# Two sessions at once. Session A takes the lock and holds its transaction open; B is started only once A holds
# it, must be seen waiting on a lock, and gets its answer only after A commits.
wait_for() {
  psql_ -At <<SQL >/dev/null
DO \$\$ BEGIN
  FOR i IN 1..200 LOOP
    PERFORM pg_stat_clear_snapshot();
    IF EXISTS (SELECT 1 FROM pg_stat_activity WHERE pid <> pg_backend_pid() AND $1) THEN RETURN; END IF;
    PERFORM pg_sleep(0.05);
  END LOOP;
  RAISE EXCEPTION 'timed out waiting for: %', \$w\$$1\$w\$;
END \$\$;
SQL
}
race() {
  local name="$1" first="$2" second="$3"
  psql_ -At -c "BEGIN" -c "SELECT $first /* $name A */" -c "SELECT pg_sleep(2) /* $name hold */" -c "COMMIT" \
    > "$data/$name.a" &
  local pid_a=$!
  wait_for "query LIKE '%/* $name hold */%' AND state = 'active'"
  psql_ -At -c "SELECT $second /* $name B */" > "$data/$name.b" &
  local pid_b=$!
  wait_for "query LIKE '%/* $name B */%' AND wait_event_type = 'Lock'"
  wait "$pid_a"; wait "$pid_b"
  echo "  $name A: $(head -n 1 "$data/$name.a")"
  echo "  $name B: $(head -n 1 "$data/$name.b")"
}
echo "Checking two concurrent sessions"
race s8 "public.redeem_package_code('SELL-RACE-GGGG', 'org_race_1', 'a@race.io', 'user_a')" \
        "public.redeem_package_code('SELL-RACE-GGGG', 'org_race_2', 'b@race.io', 'user_b')"
race s3 "public.activate_package_checkout('cs_race', 'org_race_3', 'solo', 50000, 'usd', 'pi_race', 'user_c')" \
        "public.activate_package_checkout('cs_race', 'org_race_3', 'solo', 50000, 'usd', 'pi_race', 'user_c')"
s8a="$(head -n 1 "$data/s8.a")"; s8b="$(head -n 1 "$data/s8.b")"
s3a="$(head -n 1 "$data/s3.a")"; s3b="$(head -n 1 "$data/s3.b")"
psql_ -v s8a="$s8a" -v s8b="$s8b" -v s3a="$s3a" -v s3b="$s3b" <<'SQL'
-- The four answers as settings of this session, for the check below (psql variables do not reach inside $$).
SELECT (set_config('race.s8a', :'s8a', false) || set_config('race.s8b', :'s8b', false) ||
        set_config('race.s3a', :'s3a', false) || set_config('race.s3b', :'s3b', false)) IS NULL AS race_unused \gset
DO $$
DECLARE a jsonb := current_setting('race.s8a')::jsonb; b jsonb := current_setting('race.s8b')::jsonb;
        c jsonb := current_setting('race.s3a')::jsonb; d jsonb := current_setting('race.s3b')::jsonb;
BEGIN
  -- S8: exactly one redemption; the other waited and was refused as used.
  IF NOT (a->>'ok')::boolean OR b <> '{"ok": false, "reason": "used"}'::jsonb THEN
    RAISE EXCEPTION 'S8: expected one success and one used, got % and %', a, b;
  END IF;
  IF (SELECT redeemed_org_id FROM public.package_codes WHERE code = 'SELL-RACE-GGGG') <> 'org_race_1'
     OR (SELECT count(*) FROM public.cs_recommendations WHERE payload->>'package_code' = 'SELL-RACE-GGGG') <> 1
     OR (SELECT count(*) FROM public.activation_fees WHERE metadata->>'package_code' = 'SELL-RACE-GGGG') <> 1
     OR (SELECT activation_paid_at FROM public.organization WHERE id = 'org_race_2') IS NOT NULL
     OR (SELECT count(*) FROM public.package_code_attempts WHERE organization_id = 'org_race_2' AND reason = 'used') <> 1 THEN
    RAISE EXCEPTION 'S8: the database does not show exactly one redemption';
  END IF;
  -- S3 at once: one activation, the second webhook waited and found it done.
  IF c->>'status' <> 'activated' OR d->>'status' <> 'already_done' OR c->>'allowance_id' <> d->>'allowance_id' THEN
    RAISE EXCEPTION 'S3: expected activated then already_done, got % and %', c, d;
  END IF;
  IF (SELECT count(*) FROM public.activation_fees WHERE organization_id = 'org_race_3') <> 1
     OR (SELECT count(*) FROM public.workspace_allowances WHERE organization_id = 'org_race_3') <> 1 THEN
    RAISE EXCEPTION 'S3: two webhooks at once wrote more than one fee row or grant';
  END IF;
END $$;
SQL
echo "Checking two concurrent sessions: passed"

run migrations/next-release/rollback/454_package-activation-functions.rollback.sql
run migrations/next-release/rollback/453_billing-packages-and-codes.rollback.sql
psql_ <<'SQL'
DO $$
DECLARE extra text; missing text;
BEGIN
  SELECT string_agg(kind || ' ' || item, '; ') INTO extra
    FROM (SELECT * FROM contract_fixture.schema_items EXCEPT SELECT * FROM contract_fixture.schema_before) s;
  SELECT string_agg(kind || ' ' || item, '; ') INTO missing
    FROM (SELECT * FROM contract_fixture.schema_before EXCEPT SELECT * FROM contract_fixture.schema_items) s;
  IF extra IS NOT NULL THEN RAISE EXCEPTION 'the rollbacks left: %', extra; END IF;
  IF missing IS NOT NULL THEN RAISE EXCEPTION 'the rollbacks removed: %', missing; END IF;
  -- What the functions wrote outside 453's tables stays.
  IF (SELECT count(*) FROM public.cs_recommendations WHERE created_by = 'system:package_code') = 0
     OR (SELECT count(*) FROM public.workspace_allowances WHERE set_by = 'system:stripe_checkout') = 0 THEN
    RAISE EXCEPTION 'the rollbacks removed rows they should leave';
  END IF;
END $$;
SQL
echo "Checking the rollbacks: passed"
run migrations/next-release/453_billing-packages-and-codes.sql
run migrations/next-release/454_package-activation-functions.sql
psql_ <<'SQL'
DO $$ BEGIN
  IF (SELECT count(*) FROM public.billing_packages) <> 4 THEN RAISE EXCEPTION 're-applying 453 did not seed the packages'; END IF;
  IF (SELECT count(*) FROM pg_proc WHERE proname IN ('activate_package_checkout', 'redeem_package_code',
                                                     'end_package_grant_for_payment')) <> 3 THEN
    RAISE EXCEPTION 're-applying 454 did not create the three functions';
  END IF;
END $$;
SQL
echo 'Package activation contract passed.'
