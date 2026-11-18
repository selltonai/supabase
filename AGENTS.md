# supabase - AI Agent Guide

## Purpose

`supabase` contains shared local Supabase configuration and migrations.

- **Stack**: PostgreSQL, Supabase CLI
- **Directory**: `/home/systempro/source/repo/systempro/sellton/supabase`

---

## 📚 Documentation

### Internal Architecture (ai-context/)
- ✅ [architecture.md](docs/ai-context/architecture.md) - System architecture, schema design, RLS patterns
- ✅ [data-models.md](docs/ai-context/data-models.md) - Complete database schema reference
- ✅ [api-contracts.md](docs/ai-context/api-contracts.md) - REST, Realtime, Storage, RPC contracts
- ✅ [supabase-patterns.md](docs/ai-context/supabase-patterns.md) - Supabase/CLI patterns, migrations, RLS, indexing
- ✅ [decisions.md](docs/ai-context/decisions.md) - Architecture Decision Records (ADRs)

### External Service Contracts
- ✅ [docs/cross-project/README.md](docs/cross-project/README.md) - **Critical**: Table ownership matrix
  - All services' database access patterns
  - Table ownership matrix (who writes/reads what)
  - RLS policies
  - Migration conventions

---

## Stage servers (Hetzner)

Stage Supabase runs on `supa-backoffice-stage` since 2026-11-09; production (`storagedb`) stays on `selltonai-main`.

| Server | IP | Runs | Public name |
|---|---|---|---|
| `sellton-vercel-stage` | 2.28.196.242 | selltonai `stage` (`/var/www/selltonai`) | https://stage-ver.sellton.ai |
| `selltonai-modal-stage` | 2.31.85.36 | selltonai-modal `stage` (`/opt/sellton-modal`) and selltonai-vector-api `stage` (`/opt/sellton-vector-api`, internal: `http://vector-api:8000`) | https://stage-mod.sellton.ai |
| `supa-backoffice-stage` | 49.12.253.93 | Supabase stage, MongoDB stage, Gmail API stage (`/opt/sellton/...`) | https://supabase-stage.sellton.ai, https://gmail-api.sellton.ai |
| `selltonai-main` | 46.224.151.84 | **production**: `storagedb`, `emailapi`, MongoDB, backoffice `portal` | never from a session |

Connect: `SSH_AUTH_SOCK=~/.ssh/claude-agent.sock ssh -o BatchMode=yes root@<IP> '...'` (key `~/.ssh/hetzner-core`,
loaded into that agent by a person: `ssh-agent -a ~/.ssh/claude-agent.sock`, then `ssh-add ~/.ssh/hetzner-core`).
Rules: never print a secret (names with `cut -d= -f1`; set values from stdin); back up a file before editing it;
nothing on 46.224.151.84; logs with `--tail` / `--since`, never whole.

Stage database: **[operations/hetzner-migrations/README.md](operations/hetzner-migrations/README.md#stage-server-supa-backoffice-stage-491225393)**
(layout, ports, Studio tunnel, read-only SQL). Migrations: `./operations/hetzner-migrations/migrate.sh status|plan|apply stage ...`
(stage defaults to 49.12.253.93), or a push to `stage`.

## Typical Work

- Schema migrations
- Policy changes
- Local DB config alignment
- Integration support for `selltonai`, `backoffice`, and service backends

## Commands

```bash
cd /home/systempro/source/repo/systempro/sellton/supabase

supabase start           # Start local Supabase
supabase stop            # Stop local Supabase
supabase db reset        # Reset and apply migrations
supabase migration new   # Create new migration
supabase gen types typescript --local > ../selltonai/src/types/database.ts  # Generate types
```

## Migration Conventions

- Location: `migrations/next-release/` for unreleased migrations
- Naming: `{number}_{description}.sql`
- Every migration should state:
  - What changed
  - Which projects depend on it
  - Whether application code must be updated together

## Review Hotspots

- Migration impact on all services
- RLS policy changes
- Enum type changes
- Index additions for performance
- Cross-project schema dependencies

## Table Ownership

**Critical**: See [docs/cross-project/README.md](docs/cross-project/README.md#table-ownership-matrix) for complete matrix.

Key tables:
| Table | Primary Writer | Primary Readers |
|-------|---------------|-----------------|
| campaigns | selltonai-modal | selltonai, backoffice |
| companies | selltonai-modal, crawler | selltonai, backoffice |
| contacts | selltonai-modal | selltonai, backoffice |
| tasks | selltonai-modal | selltonai, backoffice |

## Rule

Every migration should state:
- What changed
- Which projects depend on it
- Whether application code must be updated together

Treat schema work as cross-project by default.

---

**Last Updated**: June 14, 2026
**External Contracts**: [docs/cross-project/README.md](docs/cross-project/README.md) - Table ownership matrix
