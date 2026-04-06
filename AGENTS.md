# supabase - AI Agent Guide

## Purpose

`supabase` contains shared local Supabase configuration and migrations.

- **Stack**: PostgreSQL, Supabase CLI
- **Directory**: `/home/systempro/source/repo/systempro/sellton/supabase`

---

## 📚 Documentation

### Internal Architecture
- 🔲 ai-context/ (TODO - create when needed)

### External Service Contracts
- ✅ [docs/cross-project/README.md](docs/cross-project/README.md) - **Critical**: Table ownership matrix
  - All services' database access patterns
  - Table ownership matrix (who writes/reads what)
  - RLS policies
  - Migration conventions

---

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

**Last Updated**: April 6, 2026
**External Contracts**: [docs/cross-project/README.md](docs/cross-project/README.md) - Table ownership matrix
