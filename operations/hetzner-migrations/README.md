# Hetzner PostgreSQL migrations

This runner plans, applies, and audits repository SQL migrations against the self-hosted Supabase
PostgreSQL databases on Hetzner. It does not scan a release directory automatically: operators pass
the exact ordered files from the checked-out branch.

Full repository path plus SHA-256 is the migration identity. Numeric prefixes are not unique across
Sellton branches—for example, stage CRM migration `release-next/344_*` and main Backoffice migration
`release_1.3.0/344_*` are different migrations.

## Commands

Run from `selltonai-database/supabase`:

```bash
./operations/hetzner-migrations/migrate.sh status stage

./operations/hetzner-migrations/migrate.sh plan stage \
  migrations/release_1.3.0/344_email-sequence-audience-mode.sql

./operations/hetzner-migrations/migrate.sh apply stage \
  migrations/release_1.3.0/344_email-sequence-audience-mode.sql

./operations/hetzner-migrations/migrate.sh apply production \
  migrations/release_1.3.0/344_email-sequence-audience-mode.sql \
  --confirm-production
```

Files execute in the exact CLI order, one transaction per file, with `ON_ERROR_STOP`. A successful
migration and its ledger entry commit together. The runner refuses known non-transactional SQL such
as `CREATE INDEX CONCURRENTLY` and `VACUUM`, embedded transaction control, and psql meta-commands;
use a reviewed migration-specific runbook for those.

## Safety

- `plan` and `status` are read-only and do not create the ledger.
- `apply production` requires an explicit confirmation flag.
- Production apply refuses to run while the rollback PostgreSQL standby or an enabled subscription
  is active, because DDL is not propagated by the current logical-replication topology.
- Before any apply, the runner creates and validates a custom-format full backup. It retains the
  latest three automation backups per environment after a replacement succeeds.
- The server acquires an environment-specific `flock`, validates the bundle and every SHA-256, runs
  DDL as the owning `supabase_admin` role, and reloads the PostgREST schema cache after success.
- Applied records live in the private `sellton_migrations.applied_migrations` table. If a previously
  applied path has different contents, planning and applying fail instead of silently re-running it.
- Production apply requires the `main` branch and accepts only the runner and migration files
  committed exactly at `HEAD`. Every successful apply
  retains its verified manifest and exact SQL under the target runtime's
  `migrations-applied/automation/` directory.

Historical migrations applied manually remain in their hash archives and are not automatically
baselined into this ledger. Do not pass old migrations merely to populate status.

Secrets remain on Hetzner. The client only needs the approved SSH key and pinned host key; no
database password or service-role key crosses the SSH connection.
