# Hetzner PostgreSQL migrations

This runner plans, applies, and audits repository SQL migrations against the self-hosted Supabase
PostgreSQL databases on Hetzner. It does not scan a release directory automatically: operators pass
the exact ordered files from the checked-out branch, or GitHub Actions reads them from the explicit
ordered `deploy-manifest.txt` file.

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

## Automatic deployment

`.github/workflows/deploy-hetzner.yml` follows the application deployment branch convention:

- A push to `stage` applies the branch's manifest to the stage database.
- A push to `main` applies the branch's manifest to the production database.
- A manual workflow dispatch uses the selected branch and the same mapping.

The workflow checks out the immutable event commit, verifies its SHA, and creates the corresponding
local branch identity so the existing production committed-source guard still applies. It then
plans, applies, plans again, and prints the environment ledger. The remote `/opt/sellton/supabase`
checkout does not need an `operations/` directory: each run uploads an exact temporary bundle and
the server retains successful artifacts under the environment runtime path.

Configure the `stage` and `production` GitHub Environments in this repository with the
`HETZNER_SSH_PRIVATE_KEY` secret. Optional `HETZNER_SSH_HOST` and `HETZNER_SSH_USER` environment
variables override the checked-in defaults. A host override must have a matching entry in the
committed `operations/hetzner-migrations/known_hosts` file; the workflow fails before upload when the
pinned key is missing. Production Environment approval rules can be enabled in GitHub without
changing the workflow.

The workflow, runner, and every file named by the branch manifest must exist on that branch. The
repository's long-lived `stage` branch has its own migration history, so promote the complete
automation change to both branches; do not cherry-pick only the workflow file.

For each future migration:

1. On `stage`, add the SQL migration and append its stage-relative path to the branch's
   `operations/hetzner-migrations/deploy-manifest.txt`; push and verify the workflow.
2. Promote the reviewed SQL to `main` using the release path intended for production, then append
   that main-relative path to the main manifest.
3. Push `main` only after stage verification. Never reorder or remove previously deployed entries
   from either branch-local manifest.
