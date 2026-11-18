# Hetzner PostgreSQL migrations

This runner plans, applies, and audits repository SQL migrations against the self-hosted Supabase
PostgreSQL databases on Hetzner. It does not scan a release directory automatically: operators pass
the exact ordered files from the checked-out branch, or GitHub Actions reads them from the explicit
ordered `deploy-manifest.txt` file.

Full repository path plus SHA-256 is the migration identity. Numeric prefixes are not unique across
Sellton branches—for example, stage CRM migration `release-next/344_*` and main Backoffice migration
`release_1.3.0/344_*` are different migrations.

The manifest completeness check accepts an unlisted file only when its SQL bytes
exactly match a listed file. This accommodates stage and main copies of the same
already-applied migration without adding a second path to the deploy manifest.
The runner still treats the full path plus SHA-256 as its identity; hash equality
in this check does not mark an unlisted path as applied.

For the stage-to-production release after 2026-09-30, retain the production
bytes and SHA of `release_1.3.0/369_deal-activity-type-check-extension.sql` on
`main`: that path is already recorded in the production ledger. Stage applied a
different version of the same path. The production manifest keeps its 30
previously applied entries in order and appends stage-only migrations. New
`next-release/384_crm-deal-signal-activity.sql` carries the `signal` check
forward after the guarded RPC from stage migration 371. Do not replace the
applied 369 file with stage's version or add alternate-path copies of SQL
already applied under the production path. Run `plan production` against the
exact release branch before merging it into `main`.

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
`HETZNER_SSH_PRIVATE_KEY` secret. The checked-in default host is `49.12.253.93` for `stage` (since
2026-11-09) and `46.224.151.84` for `main`; the `stage` key must be authorized for `root` on 49.12.253.93.
Optional `HETZNER_SSH_HOST` and `HETZNER_SSH_USER` environment variables override the defaults. A host override must have a matching entry in the
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

## Stage server (supa-backoffice-stage, 49.12.253.93)

Stage Supabase moved off the production server on 2026-11-09 (same container names, paths and keys; the old copy on
46.224.151.84 is stopped, not deleted). `migrate.sh ... stage` now goes there by default with `~/.ssh/hetzner-core`
(through an ssh-agent); production keeps 46.224.151.84 and `~/.ssh/hetzner-api`.

| Server | IP | What runs there | Public name |
|---|---|---|---|
| `sellton-vercel-stage` | 2.28.196.242 | selltonai `stage` (`/var/www/selltonai`) | https://stage-ver.sellton.ai |
| `selltonai-modal-stage` | 2.31.85.36 | selltonai-modal `stage` (`/opt/sellton-modal`) and selltonai-vector-api `stage` (`/opt/sellton-vector-api`, internal: `http://vector-api:8000`) | https://stage-mod.sellton.ai |
| `supa-backoffice-stage` | 49.12.253.93 | Supabase stage, MongoDB stage, Gmail API stage, Caddy | https://supabase-stage.sellton.ai, https://gmail-api.sellton.ai |
| `selltonai-main` | 46.224.151.84 | **production** (`storagedb`, `emailapi`, production MongoDB, backoffice `portal`) | not from a session |

**Connect:** `ssh root@49.12.253.93` with `~/.ssh/hetzner-core` (passphrase: a person loads it once with
`ssh-agent -a ~/.ssh/claude-agent.sock` and `SSH_AUTH_SOCK=~/.ssh/claude-agent.sock ssh-add ~/.ssh/hetzner-core`;
an agent then runs `SSH_AUTH_SOCK=~/.ssh/claude-agent.sock ssh -o BatchMode=yes root@49.12.253.93 '...'`).

**Rules (agents):** schema changes only through `migrate.sh` (plan and status are read-only); never print a key or a
password (names with `cut -d= -f1`); back up a file before editing it; nothing on 46.224.151.84 (production) from a
session; never delete `volumes/db/data` or the `supabase-stage_db-config` volume (it holds `pgsodium_root.key`,
without which Vault values cannot be read).

| What | Where |
|---|---|
| Compose project | `/opt/sellton/supabase-stage` (`docker-compose.yml`, `.env` mode 600, `volumes/`) |
| Database | container `supabase-stage-db` (supabase/postgres 15.8), data in `volumes/db/data`, `127.0.0.1:55322`; pooler `127.0.0.1:55324` |
| API gateway | `supabase-stage-kong`, `127.0.0.1:55321`; public https://supabase-stage.sellton.ai through Caddy (`/opt/sellton/proxy`, `sites/supabase-stage.caddy`) |
| App keys (anon, service role) | `/opt/sellton/supabase-stage/app-env.local.txt` (root only; unchanged by the move) |
| Applied-migrations ledger | table `sellton_migrations.applied_migrations`; artifacts in `migrations-applied/` |
| Migration backups | `/opt/sellton/backups/database-migrations/stage` (made by the runner before each apply) |

```bash
# read-only SQL as the admin role
ssh root@49.12.253.93 'docker exec -i supabase-stage-db psql -X -U supabase_admin -d postgres -c "select count(*) from public.organization"'
# Studio: tunnel the gateway, then open http://localhost:55321 (dashboard login in .env, DASHBOARD_USERNAME/PASSWORD)
ssh -N -L 55321:127.0.0.1:55321 root@49.12.253.93
# health
ssh root@49.12.253.93 'cd /opt/sellton/supabase-stage && docker compose ps --format "{{.Name}} {{.Status}}"'
```

A change to `/opt/sellton/supabase-stage/.env` (Auth settings, SMTP, keys) takes effect with
`docker compose up -d` in that folder (recreates what changed). Changing `JWT_SECRET` or the keys breaks every app
that holds the old anon or service-role key: stage web, stage API, stage Gmail API, the backoffice.

