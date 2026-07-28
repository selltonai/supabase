# Hetzner PostgreSQL memory tuning

This runbook records the production PostgreSQL memory budget used by Usage Analytics Phase C. It is operational configuration, not a schema migration: do not put these commands in the migration runner or execute them as part of an application deploy.

## Live configuration

Applied on 2026-07-28 to the production `supabase-db` container with PostgreSQL `ALTER SYSTEM`:

| Setting | Value | Reason |
|---|---:|---|
| `shared_buffers` | `2GB` | Gives the database a durable cache without consuming an unsafe share of the mixed-use host. |
| `effective_cache_size` | `8GB` | Lets the planner account for PostgreSQL plus operating-system cache; it does not allocate 8 GiB. |
| `work_mem` | `8MB` | Reduces small sort/hash spills while keeping the 100-connection worst case bounded. |
| `maintenance_work_mem` | `256MB` | Speeds controlled maintenance and index work without being a per-query allocation. |

The host audit recorded 30.6 GiB RAM, 16 vCPUs, no Docker memory limit on `supabase-db`, and about 10.9 GiB available memory. The host also runs production and stage Supabase/MongoDB workloads, so this must not be tuned as a dedicated PostgreSQL server.

`shared_buffers` needs a PostgreSQL restart. The other three settings are reloadable, but all four were applied together and the healthy database container was restarted once. The persistent data directory is a host bind mount, so `postgresql.auto.conf` written by `ALTER SYSTEM` survives recreation.

## Verification

Run this from the Hetzner host after every memory adjustment. It exposes configuration and health only; it does not query customer rows.

```bash
docker exec supabase-db psql -X -v ON_ERROR_STOP=1 -U supabase_admin -d postgres -P pager=off -At -F '|' -c "SELECT name, setting, pending_restart FROM pg_settings WHERE name = ANY (ARRAY['shared_buffers', 'effective_cache_size', 'work_mem', 'maintenance_work_mem']) ORDER BY name; SELECT 1;"
docker inspect supabase-db supabase-auth supabase-storage supabase-pooler --format '{{.Name}}|{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}'
docker stats --no-stream --format '{{.Name}}|{{.MemUsage}}|{{.CPUPerc}}|{{.PIDs}}' supabase-db
awk '/MemAvailable/ {print $2 * 1024}' /proc/meminfo
```

Acceptance is `pending_restart = false`, `SELECT 1` succeeds, database/Auth/Storage/Pooler are healthy, and the host retains enough available memory for the co-located services. At the 2026-07-28 verification the database container used 1.23 GiB and the host had about 10.35 GiB available.

## Rollback

Use only if post-change health checks or workload monitoring show memory pressure. These commands return to the values in `/etc/postgresql/postgresql.conf`; `shared_buffers` takes effect after the restart.

```bash
docker exec supabase-db psql -X -v ON_ERROR_STOP=1 -U supabase_admin -d postgres -c "ALTER SYSTEM RESET shared_buffers;"
docker exec supabase-db psql -X -v ON_ERROR_STOP=1 -U supabase_admin -d postgres -c "ALTER SYSTEM RESET effective_cache_size;"
docker exec supabase-db psql -X -v ON_ERROR_STOP=1 -U supabase_admin -d postgres -c "ALTER SYSTEM RESET work_mem;"
docker exec supabase-db psql -X -v ON_ERROR_STOP=1 -U supabase_admin -d postgres -c "ALTER SYSTEM RESET maintenance_work_mem;"
docker restart --timeout 30 supabase-db
```

Re-run the verification block before declaring recovery complete.

## Re-audit triggers

Repeat the capacity audit before any further increase when any of these change:

- `max_connections`, pooling behavior, or concurrent analytics jobs;
- production/stage container placement or memory limits;
- workload growth that materially changes temp-file volume or active-query concurrency; or
- the Usage Analytics projection backfill/load test begins.

Do not increase global `work_mem` solely to avoid one query spill. The durable fix is the usage projection; use a scoped, measured setting only if a later benchmark demonstrates a need.
