# Architecture Decision Records (ADRs) - Supabase

## Overview

This document captures the key architecture decisions made for the **selltonai-database/supabase** project. These ADRs serve as the historical record of why certain choices were made, their consequences, and the alternatives that were considered.

For complete project context, see:
- [Architecture](architecture.md) - System design and structure
- [Data Models](data-models.md) - Database schema documentation
- [API Contracts](api-contracts.md) - API and service contracts
- [Supabase Patterns](supabase-patterns.md) - Supabase-specific implementation patterns

---

## ADR-001: Use Supabase as Database Infrastructure

**Date**: 2024-Q4  
**Status**: Accepted  
**Context**: Database platform selection

### Problem
Need a database platform that provides:
- Multi-tenancy support with data isolation
- REST API access for frontend services
- Realtime capabilities for live updates
- Row-level security for fine-grained access control
- Storage for file uploads
- Authentication integration (Clerk compatible)
- Easy local development
- Scalable for production

### Decision
Use **Supabase** (PostgreSQL) as the primary database infrastructure for all Sellton services.

### Consequences

#### Positive
- ✅ Full PostgreSQL feature set (JSONB, enums, indexes, constraints)
- ✅ Built-in REST API reduces backend boilerplate
- ✅ Row Level Security (RLS) provides multi-tenancy out of the box
- ✅ Realtime subscriptions via WebSockets
- ✅ Storage service for file uploads
- ✅ Authentication integration with Clerk JWT tokens
- ✅ Dashboard for database management and monitoring
- ✅ CLI for local development
- ✅ Free tier for development and testing
- ✅ Open source with active community

#### Negative
- ⚠️ Rate limits on REST API (50 req/sec by default)
- ⚠️ Connection pooling required for high concurrency
- ⚠️ Some PostgreSQL extensions not available on shared plans
- ⚠️ Vendor lock-in to Supabase ecosystem
- ⚠️ Cost can increase with usage (Pro plan for production)

### Alternatives Considered
- **Self-hosted PostgreSQL**: More control but more operational overhead
- **AWS RDS Aurora**: Expensive, complex setup, no built-in REST API
- **Firebase**: Limited query capabilities, no PostgreSQL features
- **MongoDB Atlas**: Poor support for complex relational queries
- **PlanetScale**: Good alternative but different feature set

### Implementation
- Created Supabase project with PostgreSQL 15
- Configured RLS policies on all public tables
- Set up authentication with Clerk JWT validation
- Created storage buckets for different file types
- Deployed to production with Pro plan

---

## ADR-002: Tenant Isolation via Organization Context

**Date**: 2024-Q4  
**Status**: Accepted  
**Context**: Multi-tenancy strategy

### Problem
Need to ensure that each organization can only access its own data, with multiple users potentially belonging to multiple organizations.

### Decision
Use **organization_id column** on all tables combined with **Row Level Security (RLS)** policies and a **context variable** for filtering.

The approach:
1. Every table has an `organization_id` column (except auth tables)
2. RLS policies check `organization_id = current_setting('app.current_org_id', true)`
3. Frontend services set the context via `set_current_org_id()` RPC before queries
4. Backend services use service role key (bypasses RLS) but filter manually

### Consequences

#### Positive
- ✅ Simple, consistent multi-tenancy pattern
- ✅ Database-level enforcement (can't be bypassed by application bugs)
- ✅ Easy to understand and audit
- ✅ Works with all query types (SELECT, INSERT, UPDATE, DELETE)
- ✅ Supports user switching between organizations

#### Negative
- ⚠️ Requires setting context before every query
- ⚠️ Context is session-based (not per-request)
- ⚠️ Service role bypasses RLS (requires careful access control)
- ⚠️ Slight performance overhead for RLS checks

### Alternatives Considered
- **JWT claims**: Encode org_id in JWT (Clerk doesn't support multiple orgs well)
- **Schema per tenant**: Create separate schema for each org (complex, hard to query across)
- **Row-level filtering in app**: Application-level filtering only (less secure)
- **Separate databases**: One DB per org (scaling nightmare)

### Implementation
```sql
-- Standard pattern for all tables
CREATE POLICY "Users can view data for their organization"
  ON table_name FOR SELECT
  USING (organization_id = current_setting('app.current_org_id', true));

CREATE POLICY "Users can insert data for their organization"
  ON table_name FOR INSERT
  WITH CHECK (organization_id = current_setting('app.current_org_id', true));
```

-- Context setting function
CREATE OR REPLACE FUNCTION public.set_current_org_id(org_id text)
RETURNS text
LANGUAGE plpgsql
AS $$ BEGIN PERFORM set_config('app.current_org_id', org_id, true); RETURN org_id; END; $$;

-- Service role bypasses RLS (for backend services)
```

---

## ADR-003: Service Role Key for Backend Services

**Date**: 2024-Q4  
**Status**: Accepted  
**Context**: Backend service access strategy

### Problem
Backend services (selltonai-modal, backoffice, crawler) need to perform operations that:
- Access data across all organizations (admin operations)
- Bypass RLS for data processing
- Perform batch operations efficiently
- Have full read/write access

But we still need security and auditability.

### Decision
Use **Supabase Service Role Key** for backend services, which:
- Bypasses all RLS policies
- Has full read/write access to all tables
- Used only by trusted backend services

Frontend services (selltonai, sellton-onboard) use **Anon Key** which:
- Enforces all RLS policies
- Only accesses data for the current organization

### Consequences

#### Positive
- ✅ Backend services have full access for data processing
- ✅ Frontend services are automatically restricted by RLS
- ✅ No need to maintain separate policies for admin access
- ✅ Service role key can be rotated independently
- ✅ Simple access pattern (one key per service type)

#### Negative
- ⚠️ Service role key is powerful (compromise = full data access)
- ⚠️ Must never be exposed to frontend
- ⚠️ Backend services must still filter by organization_id manually
- ⚠️ Key rotation requires coordination across all services
- ⚠️ Audit trail shows service role, not specific user

### Alternatives Considered
- **Custom admin role**: Create separate role with specific permissions
- **Per-service roles**: Different role for each backend service
- **RLS with user context**: Pass user context to backend (complex, breaks abstraction)

### Implementation
```typescript
// Backend service (selltonai-modal)
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY  // Bypasses RLS
);

// Always filter by organization_id manually
export async function getCompanies(orgId: string) {
  return supabase
    .from('companies')
    .select('*')
    .eq('organization_id', orgId);  // Manual filter
}
```

```typescript
// Frontend service (selltonai)
const supabase = createClient(
  import.meta.env.VITE_SUPABASE_URL,
  import.meta.env.VITE_SUPABASE_ANON_KEY  // Enforces RLS
);

// RLS automatically filters by organization_id
```

### Key Distribution
| Service | Key Type | Access Level |
|---------|----------|--------------|
| selltonai | Anon Key | RLS enforced |
| selltonai-onboard | Anon Key | RLS enforced |
| selltonai-modal | Service Role | RLS bypassed |
| backoffice | Service Role | RLS bypassed |
| selltonai-crawler | Service Role | RLS bypassed |
| selltonai-gmail-api | Service Role | RLS bypassed |
| selltonai-vector-api | Service Role | RLS bypassed |

---

## ADR-004: JSONB for Flexible Data Storage

**Date**: 2024-Q4  
**Status**: Accepted  
**Context**: Handling variable and evolving data structures

### Problem
The Sellton platform deals with data that:
- Varies by provider (B2B API, AI providers, CRM imports)
- Evolves over time (new fields, changing structures)
- Contains nested hierarchical data (enrichment results, ICP scores)
- Requires querying within the data (filtering, sorting)

Traditional relational schema would require frequent migrations for every small change.

### Decision
Use **JSONB columns** for flexible, semi-structured data in the following tables:

#### Companies Table
| Column | Purpose | Queryable |
|--------|---------|-----------|
| `b2b_result` | Raw B2B API response | ❌ No |
| `b2b_enrichment` | Normalized enrichment data | ❌ No |
| `icp_score` | ICP scoring results | ✅ Yes (GIN index) |
| `deep_research` | Deep research v1 results | ❌ No |
| `deep_research_v2` | Deep research v2 results | ❌ No |
| `outreach_strategy` | AI-generated strategy | ❌ No |

#### Other Tables
| Table | Column | Purpose |
|-------|--------|---------|
| contacts | `location` | Location data |
| contacts | `analysis` | AI analysis of profile |
| onboarding_research | `core_offer` | Core product offering |
| onboarding_research | `value_propositions` | Value propositions |
| onboarding_research | `icp_hypotheses` | ICP hypotheses |

### Consequences

#### Positive
- ✅ Schema flexibility without migrations
- ✅ Easy to iterate on enrichment logic
- ✅ Can store provider-specific data in same table
- ✅ PostgreSQL JSONB supports indexing and queries
- ✅ Can evolve data structure over time
- ✅ Reduces number of tables needed

#### Negative
- ⚠️ No database-level validation of structure
- ⚠️ Harder to query specific nested fields
- ⚠️ No foreign keys within JSONB
- ⚠️ Requires application-level validation
- ⚠️ Joins within JSONB are not possible

### Mitigation Strategies
1. **Pydantic models** for validation at application layer
2. **Documentation** of expected JSONB structures
3. **GIN indexes** for frequently queried JSONB fields
4. **Extract common fields** to top-level columns when heavily used
5. **Type generation** to provide TypeScript types for JSONB structures

### Example Query
```typescript
// Query companies with ICP score > 70
const { data } = await supabase
  .from('companies')
  .select('*')
  .eq('organization_id', orgId)
  .gt('icp_score->>score', 70)
  .order('icp_score->>score', { ascending: false });
```

---

## ADR-005: Enum Types for Constrained Values

**Date**: 2024-Q4  
**Status**: Accepted  
**Context**: Type safety for constrained string values

### Problem
Many columns have a fixed set of possible values (status, type, stage, etc.). Using plain text columns:
- Allows invalid values
- No type safety
- Hard to document valid values
- No validation at database level

### Decision
Use **PostgreSQL enum types** for all constrained string values. This provides:
- Database-level validation
- Type safety in TypeScript
- Self-documenting schema
- Easy to query and filter

### Consequences

#### Positive
- ✅ Database enforces valid values
- ✅ TypeScript types can be generated from enum definitions
- ✅ Self-documenting (values are visible in schema)
- ✅ Better query performance (enums are small integers internally)
- ✅ Easy to add new values with ALTER TYPE

#### Negative
- ⚠️ Adding new values requires migration (ALTER TYPE ... ADD VALUE)
- ⚠️ Removing values is complex (requires data migration)
- ⚠️ Enum changes require coordination with all services
- ⚠️ Application code must handle all enum values

### Current Enum Types

```sql
-- Company processing status
CREATE TYPE company_processing_status AS ENUM (
  'scheduled',
  'processing',
  'processed',
  'failed',
  'blocked_by_icp',
  'imported'
);

-- Contact pipeline stage
CREATE TYPE pipeline_stage AS ENUM (
  'prospect',
  'appointment_requested',
  'qualified',
  'proposal',
  'negotiation',
  'won',
  'lost',
  'not_interested'
);

-- Task type and status
CREATE TYPE task_type AS ENUM (
  'company_verification',
  'email_copy',
  'call_script',
  'follow_up_email'
);

CREATE TYPE task_status AS ENUM (
  'pending',
  'approved',
  'rejected',
  'completed',
  'cancelled'
);

-- Campaign status
CREATE TYPE campaign_status AS ENUM (
  'draft',
  'active',
  'paused',
  'completed'
);

-- CRM import status
CREATE TYPE import_status AS ENUM (
  'raw',
  'extracted',
  'failed'
);

-- Record classification
CREATE TYPE record_type AS ENUM (
  'unknown',
  'company',
  'person'
);
```

### Adding New Enum Values
```sql
-- Non-breaking: Add new value to existing enum
ALTER TYPE company_processing_status ADD VALUE 'new_status';

-- Breaking: Rename enum value (requires data migration)
-- Not recommended - create new enum instead
```

### Best Practices
1. **Prefix enum types** with table name (e.g., `campaign_status` not just `status`)
2. **Use lowercase** with underscores for enum values
3. **Document enum purpose** with COMMENT ON TYPE
4. **Coordinate changes** with all services that use the enum
5. **Add validation** in application layer (Pydantic, Zod)
6. **Generate TypeScript types** from enum definitions

---

## ADR-006: Migration Organization by Release

**Date**: 2025-Q1  
**Status**: Accepted  
**Context**: Database migration management

### Problem
As the project grows, we need to:
- Group related migrations together
- Track which migrations are in which release
- Support rollback of specific releases
- Maintain migration history
- Deploy to multiple environments (local, staging, production)

### Decision
Organize migrations by **semantic version releases** with the following structure:

```
selltonai-database/supabase/migrations/
├── release_1.0.0/          # Initial release
│   ├── 001_create_organizations.sql
│   ├── 002_create_users.sql
│   ├── 003_create_user_organizations.sql
│   └── MANIFEST.md
│
├── release_1.0.1/          # Bug fixes
│   ├── 004_fix_user_org_constraint.sql
│   └── MANIFEST.md
│
├── release_1.1.0/          # Feature release
│   ├── 005_add_campaigns_table.sql
│   ├── 006_add_companies_table.sql
│   └── MANIFEST.md
│
├── release_1.2.0/          # Latest stable release
│   ├── 254_create_linkedin_accounts.sql
│   ├── 255_create_linkedin_action_log.sql
│   └── MANIFEST.md
│
└── next-release/            # Unreleased (staging)
    ├── 999_new_feature.sql
    └── MANIFEST.md
```

Each migration file has a **standard header** with metadata:
```sql
-- Migration: Description of what this migration does
-- Date: YYYY-MM-DD
-- Author: Developer Name
-- Description: Detailed description of changes
-- Affected services: selltonai, selltonai-modal, backoffice, etc.
-- Requires code changes: Yes/No - if application code must be updated together
-- Breaking: Yes/No - if this is a breaking change

-- SQL changes below this line
```

### Consequences

#### Positive
- ✅ Clear version history
- ✅ Easy to see what changed in each release
- ✅ Can deploy specific releases
- ✅ MANIFEST.md documents release contents
- ✅ Easy to find related migrations

#### Negative
- ⚠️ More directories to manage
- ⚠️ Need to move migrations from next-release to release_X.Y.Z
- ⚠️ MANIFEST.md files require maintenance
- ⚠️ Release numbering must be coordinated

### Alternatives Considered
- **Flat structure**: All migrations in one directory (hard to track releases)
- **Date-based**: `migrations/YYYY-MM-DD_description.sql` (no release grouping)
- **Git tags only**: Use git tags for releases (no filesystem organization)

### Implementation
**MANIFEST.md Template**:
```markdown
# Release X.Y.Z Migration Manifest

## Date
YYYY-MM-DD

## Migrations
- 001_create_table_x.sql - Create table X for feature Y
- 002_add_column_z.sql - Add column Z to table X

## Dependencies
- Requires release X.Y.Z-1 to be applied first
- Requires application code updates in selltonai-modal

## Breaking Changes
- None

## Rollback Instructions
1. Revert migration 002
2. Revert migration 001

## Notes
- Additional context for deployment
- Testing requirements
```

**Migration Workflow**:
1. Create migration: `supabase migration new migration_name`
2. Add to `next-release/` directory
3. Write SQL with standard header
4. Test locally: `supabase db reset`
5. Move to `release_X.Y.Z/` when ready
6. Update MANIFEST.md
7. Deploy to production

---

## ADR-007: File Storage in Supabase Storage

**Date**: 2025-Q1  
**Status**: Accepted  
**Context**: File storage strategy

### Problem
Need to store various types of files:
- Organization documents (PDFs, Word, etc.)
- User avatars
- Temporary processing files
- CSV imports

Requirements:
- Organized by organization
- Secure access (RLS-equivalent for files)
- Easy upload/download from all services
- CDN-like performance for public files

### Decision
Use **Supabase Storage** with a hierarchical bucket structure:

```
Supabase Storage
├── organization_files/      # Main document storage
│   ├── org_{org_id}/
│   │   ├── {file_id}.pdf
│   │   ├── {file_id}.docx
│   │   └── ...
│   └── ... (other orgs)
│
├── avatars/                # User profile pictures
│   ├── {user_id}.jpg
│   └── ...
│
├── temp/                   # Temporary processing files
│   └── {session_id}/
│       └── {temp_file}
│
└── crm_imports/            # CRM CSV uploads
    └── org_{org_id}/
        └── {import_id}.csv
```

### Consequences

#### Positive
- ✅ Built into Supabase (no additional service needed)
- ✅ Same auth as database (anon key and service role)
- ✅ Can apply RLS-like policies via path prefixes
- ✅ CDN for public URLs
- ✅ Easy to use from all Supabase clients
- ✅ Automatic cleanup of temp files

#### Negative
- ⚠️ Not as feature-rich as dedicated storage (S3, GCS)
- ⚠️ Limited file size (50MB default, 5GB max)
- ⚠️ Cost based on storage + bandwidth
- ⚠️ No versioning (would need custom implementation)

### Alternatives Considered
- **AWS S3**: More features but separate auth and service
- **Google Cloud Storage**: Similar to S3
- **Self-hosted**: Complex to maintain
- **Firebase Storage**: Limited features, different ecosystem

### Implementation
```typescript
// Upload file
const { data, error } = await supabase
  .storage
  .from('organization_files')
  .upload(`org_${organizationId}/${fileId}.pdf`, file, {
    cacheControl: '3600',
    upsert: false,
    contentType: 'application/pdf'
  });

// Download file
const { data, error } = await supabase
  .storage
  .from('organization_files')
  .download(`org_${organizationId}/${fileId}.pdf`);

// Get public URL
const { data: { publicUrl } } = supabase
  .storage
  .from('organization_files')
  .getPublicUrl(`org_${organizationId}/${fileId}.pdf`);

// List files for organization
const { data, error } = await supabase
  .storage
  .from('organization_files')
  .list(`org_${organizationId}/`);
```

---

## ADR-008: Realtime Updates via WebSockets

**Date**: 2025-Q1  
**Status**: Accepted  
**Context**: Real-time data synchronization

### Problem
Users need to see updates in real-time:
- Campaign status changes
- New companies being processed
- Task creation and updates
- Onboarding progress
- Collaborative editing in backoffice

Without polling, which is inefficient and causes delay.

### Decision
Use **Supabase Realtime** (WebSocket-based) for all real-time updates, with the following patterns:

1. **Organization-scoped channels**: `org_{org_id}_{table}`
2. **Filter by organization_id**: Always include in Postgres changes filter
3. **Broadcast messages**: For custom events beyond database changes
4. **Automatic cleanup**: Remove channels when components unmount

### Consequences

#### Positive
- ✅ Real-time updates without polling
- ✅ Low latency (WebSocket connection)
- ✅ Scales well (Supabase handles connection management)
- ✅ Works across all frontend services
- ✅ Can subscribe to multiple tables
- ✅ Broadcast capability for custom events

#### Negative
- ⚠️ Requires WebSocket connection (firewall issues possible)
- ⚠️ Battery drain on mobile (connection stays open)
- ⚠️ Memory usage for many subscriptions
- ⚠️ Reconnection logic needed for drops
- ⚠️ Rate limits on connections (100 per project)

### Alternatives Considered
- **Polling**: Simple but inefficient (high latency, many requests)
- **Server-Sent Events (SSE)**: One-way only, less flexible
- **Webhooks**: Would require backend service to fan out
- **Pusher**: Additional service and cost
- **Firebase Realtime**: Different ecosystem

### Implementation
```typescript
// Subscribe to changes
const channel = supabase
  .channel(`org_${organizationId}_campaigns`)
  .on(
    'postgres_changes',
    {
      event: '*',
      schema: 'public',
      table: 'campaigns',
      filter: `organization_id=eq.${organizationId}`
    },
    (payload) => {
      console.log('Campaign changed:', payload.eventType, payload.new);
      // Update local state
      updateCampaigns(payload.new);
    }
  )
  .subscribe();

// Broadcast custom message
const channel = supabase.channel('refresh_cache');
channel.send({
  type: 'broadcast',
  event: 'invalidate_campaigns',
  payload: { organization_id: orgId }
});

// Receive broadcast
const channel = supabase
  .channel('refresh_cache')
  .on('broadcast', { event: 'invalidate_campaigns' }, (payload) => {
    refreshCampaignsCache(payload.organization_id);
  })
  .subscribe();

// Cleanup
supabase.removeChannel(channel);
```

### Common Realtime Channels
| Channel Pattern | Purpose | Typical Usage |
|----------------|---------|---------------|
| `org_{id}_campaigns` | Campaign updates | selltonai campaign list |
| `org_{id}_companies` | Company updates | selltonai company list |
| `org_{id}_tasks` | Task creation | selltonai task inbox |
| `org_{id}_onboarding` | Onboarding progress | sellton-onboard status |
| `refresh_cache` | Cache invalidation | All services |
| `user_{id}_presence` | User presence | backoffice collaboration |

---

## ADR-009: Clerk Integration for Authentication

**Date**: 2025-Q1  
**Status**: Accepted  
**Context**: Authentication and user management

### Problem
Need authentication that:
- Supports multiple organizations per user
- Integrates with Supabase RLS
- Provides JWT tokens for API access
- Handles user sign-up and management
- Supports social login (Google, etc.)

### Decision
Use **Clerk** as the authentication provider with **Supabase JWT validation**:

```
User → Clerk Auth → JWT Token → Supabase
                  ↓
          Clerk Webhook → selltonai-modal → Sync to Supabase
```

1. Clerk handles all auth UI and flows
2. Clerk generates JWT tokens with custom claims
3. Supabase validates Clerk JWT tokens
4. Clerk webhooks notify backend of user/organization changes
5. Backend syncs Clerk data to Supabase tables

### Consequences

#### Positive
- ✅ Beautiful auth UIs (pre-built components)
- ✅ Handles all auth flows (sign-up, sign-in, password reset, etc.)
- ✅ Multi-org support out of the box
- ✅ Social login (Google, GitHub, etc.)
- ✅ Custom JWT claims for org context
- ✅ Webhooks for real-time sync
- ✅ Fraud detection and security

#### Negative
- ⚠️ Vendor lock-in to Clerk
- ⚠️ Additional service cost
- ⚠️ JWT validation must be configured in Supabase
- ⚠️ Webhook handling adds backend complexity
- ⚠️ Token expiration requires refresh logic

### Alternatives Considered
- **Supabase Auth**: Built-in but less feature-rich
- **Auth0**: More expensive, similar features
- **Firebase Auth**: Different ecosystem
- **NextAuth.js**: More code to maintain
- **Custom auth**: Too much work for basic auth

### Implementation
**Clerk Configuration**:
```javascript
// In Clerk dashboard
// Add custom claims to JWT
{
  "org_id": "current organization ID",
  "org_name": "current organization name",
  "org_role": "user role in org",
  "email": "user email"
}
```

**Supabase JWT Configuration**:
```sql
-- Create JWT validation function
CREATE OR REPLACE FUNCTION public.validate_clerk_jwt()
RETURNS boolean
LANGUAGE plpgsql
AS $$ ... $$;

-- Configure in Supabase Auth settings
-- Set JWT secret from Clerk
```

**Frontend Usage**:
```typescript
import { useUser } from '@clerk/clerk-react';

function MyComponent() {
  const { user, isSignedIn } = useUser();
  
  if (!isSignedIn) return <SignInButton />;
  
  // user.org_id is available from Clerk
  return <App orgId={user.org_id} />;
}
```

**Webhook Handling (selltonai-modal)**:
```python
from clerk import Clerk
from supabase import create_client

@clerk_webhook
async def handle_user_created(user: dict):
    """Sync new user to Supabase"""
    supabase = create_client(supabase_url, supabase_key)
    
    # Insert or update user
    supabase.table('users').upsert({
        'id': user['id'],
        'email': user['email_addresses'][0]['email_address'],
        'firstname': user['first_name'],
        'lastname': user['last_name']
    }).execute()

@clerk_webhook
async def handle_organization_created(org: dict):
    """Sync new organization to Supabase"""
    supabase.table('organizations').upsert({
        'id': org['id'],
        'name': org['name']
    }).execute()

@clerk_webhook
async def handle_membership_created(membership: dict):
    """Sync user-org membership to Supabase"""
    supabase.table('user_organizations').upsert({
        'user_id': membership['user_id'],
        'organization_id': membership['organization_id'],
        'role': membership['role']
    }).execute()
```

---

## ADR-010: TypeScript Type Generation

**Date**: 2025-Q2  
**Status**: Accepted  
**Context**: Frontend type safety

### Problem
Frontend services need TypeScript types that match the database schema:
- Table types
- Column types
- Relationship types
- Enum types

Manual type definition is error-prone and hard to maintain.

### Decision
Use **Supabase CLI** to generate TypeScript types from the database schema:

```bash
# Generate types from local database
supabase gen types typescript --local > ../../selltonai/src/types/database.ts

# Generate from remote database
supabase gen types typescript --db-url $SUPABASE_URL > database.ts
```

This generates:
- Interfaces for each table
- Types for each column
- Types for relationships
- Enum types
- JSON types for JSONB columns

### Consequences

#### Positive
- ✅ Always in sync with database schema
- ✅ Reduces manual type definition errors
- ✅ Includes all tables, columns, and relationships
- ✅ Type-safe queries
- ✅ Auto-complete in IDE
- ✅ Easy to regenerate after schema changes

#### Negative
- ⚠️ Generated types are read-only (can't extend)
- ⚠️ May include internal tables not used by frontend
- ⚠️ JSONB types may need manual refinement
- ⚠️ Requires running generator after schema changes

### Alternatives Considered
- **Manual types**: Error-prone, hard to maintain
- **Prisma**: Would require switching from Supabase client
- **Hasura**: Different ecosystem
- **Custom scripts**: More work to maintain

### Implementation
**Generated Types File**: `src/types/database.ts`

```typescript
// Auto-generated by supabase gen types
// DO NOT EDIT DIRECTLY

export interface Database {
  public: {
    Tables: {
      organizations: {
        Row: {
          id: string;
          name: string;
          created_at: string;
          updated_at: string;
        };
        Insert: {
          id: string;
          name: string;
          created_at?: string;
          updated_at?: string;
        };
        Update: {
          id?: string;
          name?: string;
          created_at?: string;
          updated_at?: string;
        };
      };
      // ... other tables
    };
    Enums: {
      company_processing_status: 'scheduled' | 'processing' | 'processed' | 'failed' | 'blocked_by_icp' | 'imported';
      // ... other enums
    };
  };
}

// Usage
type Organization = Database['public']['Tables']['organizations']['Row'];
type OrganizationInsert = Database['public']['Tables']['organizations']['Insert'];
type ProcessingStatus = Database['public']['Enums']['company_processing_status'];
```

**Workflow**:
1. Make schema changes in migrations
2. Apply migrations: `supabase db reset`
3. Generate types: `supabase gen types typescript --local`
4. Commit types file with schema changes
5. Use types in frontend code

---

## ADR-011: Composite Indexes for Common Queries

**Date**: 2025-Q2  
**Status**: Accepted  
**Context**: Query performance optimization

### Problem
Many queries filter by multiple columns simultaneously:
- `organization_id` + `status` (most common)
- `organization_id` + `created_at`
- `campaign_id` + `processing_status`

Without composite indexes, PostgreSQL may use only one index per query or do full scans.

### Decision
Create **composite indexes** for all common query patterns, following this priority:

1. **Organization + Status**: `idx_{table}_org_status`
2. **Organization + Created At**: `idx_{table}_org_created_at`
3. **Organization + Foreign Key**: `idx_{table}_org_{fk}`
4. **Single column**: `idx_{table}_{column}` for frequently filtered columns
5. **Partial indexes**: For queries with WHERE clauses

### Consequences

#### Positive
- ✅ Faster queries (index-only scans possible)
- ✅ Better query planning by PostgreSQL
- ✅ Reduced I/O (fewer rows need to be examined)
- ✅ Scales better with data growth

#### Negative
- ⚠️ More indexes = more write overhead
- ⚠️ More storage space used
- ⚠️ Need to monitor index usage
- ⚠️ Unused indexes should be removed

### Alternatives Considered
- **Single-column indexes only**: Less optimal for multi-column queries
- **No indexes**: Full table scans (unacceptable for production)
- **Index everything**: Too much overhead, storage bloat

### Implementation
```sql
-- Organization + Status (most common pattern)
CREATE INDEX idx_campaigns_org_status ON campaigns(organization_id, status);
CREATE INDEX idx_companies_org_status ON companies(organization_id, processing_status);
CREATE INDEX idx_tasks_org_status ON tasks(organization_id, status);

-- Organization + Created At (for time-based queries)
CREATE INDEX idx_campaigns_org_created_at ON campaigns(organization_id, created_at);
CREATE INDEX idx_companies_org_created_at ON companies(organization_id, created_at);

-- Organization + Foreign Key
CREATE INDEX idx_companies_org_campaign_id ON companies(organization_id, campaign_id) 
  WHERE campaign_id IS NOT NULL;
CREATE INDEX idx_tasks_org_company_id ON tasks(organization_id, company_id) 
  WHERE company_id IS NOT NULL;

-- Single column (for queries filtering by status only)
CREATE INDEX idx_campaigns_status ON campaigns(status);
CREATE INDEX idx_companies_processing_status ON companies(processing_status);

-- Partial indexes (for specific status values)
CREATE INDEX idx_campaigns_org_active ON campaigns(organization_id) 
  WHERE status = 'active';
CREATE INDEX idx_companies_org_processed ON companies(organization_id) 
  WHERE processing_status = 'processed';
```

**Query Examples Using Indexes**:
```typescript
// Uses idx_campaigns_org_status
const { data } = await supabase
  .from('campaigns')
  .select('*')
  .eq('organization_id', orgId)
  .eq('status', 'active');

// Uses idx_companies_org_created_at
const { data } = await supabase
  .from('companies')
  .select('*')
  .eq('organization_id', orgId)
  .order('created_at', { ascending: false })
  .limit(50);
```

---

## ADR-012: Soft Deletes with deleted_at Column

**Date**: 2025-Q3  
**Status**: Proposed  
**Context**: Data deletion strategy

### Problem
Hard deletes (DELETE FROM table) have drawbacks:
- Data is permanently lost
- Hard to recover from mistakes
- Breaks foreign key references
- Can't audit what was deleted
- Users expect to be able to restore

### Decision
**Proposed**: Implement **soft deletes** using a `deleted_at` timestamp column:

1. Add `deleted_at timestamptz` column to important tables
2. Update RLS policies to filter out deleted records by default
3. Add `is_deleted` computed column for convenience
4. Create separate policies for viewing deleted records
5. Provide `restore` functionality

### Consequences

#### Positive
- ✅ Data can be recovered
- ✅ Full audit trail of deletions
- ✅ Can query deleted records if needed
- ✅ User-friendly (undo delete)
- ✅ Consistent with many SaaS patterns

#### Negative
- ⚠️ More storage (deleted records still exist)
- ⚠️ Query complexity (must filter out deleted)
- ⚠️ Index bloat (indexes include deleted records)
- ⚠️ Need cleanup process for old deleted records

### Implementation (Proposed)
```sql
-- Add deleted_at column
ALTER TABLE campaigns ADD COLUMN deleted_at timestamptz;

-- Add index for deleted_at
CREATE INDEX idx_campaigns_deleted_at ON campaigns(deleted_at) WHERE deleted_at IS NOT NULL;

-- Add computed column
ALTER TABLE campaigns ADD COLUMN is_deleted boolean 
  GENERATED ALWAYS AS (deleted_at IS NOT NULL) STORED;

-- Update RLS policies to exclude deleted
CREATE POLICY "Users can view active data for their organization"
  ON campaigns FOR SELECT
  USING (
    organization_id = current_setting('app.current_org_id', true) AND
    deleted_at IS NULL
  );

-- Policy for viewing deleted (admin only)
CREATE POLICY "Admins can view deleted data for their organization"
  ON campaigns FOR SELECT
  USING (
    organization_id = current_setting('app.current_org_id', true) AND
    deleted_at IS NOT NULL
  );

-- Soft delete function
CREATE OR REPLACE FUNCTION public.soft_delete_campaign(campaign_id uuid)
RETURNS boolean
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE campaigns 
  SET deleted_at = now() 
  WHERE id = campaign_id 
    AND organization_id = current_setting('app.current_org_id', true);
  RETURN FOUND;
END;
$$;

-- Restore function
CREATE OR REPLACE FUNCTION public.restore_campaign(campaign_id uuid)
RETURNS boolean
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE campaigns 
  SET deleted_at = NULL 
  WHERE id = campaign_id 
    AND organization_id = current_setting('app.current_org_id', true);
  RETURN FOUND;
END;
$$;
```

**Current State**: Not yet implemented. Most tables do not have soft delete. Consider for future implementation.

---

## Summary of Active Decisions

| ADR | Decision | Impact | Status |
|-----|----------|--------|--------|
| 001 | Supabase as database | Platform choice | ✅ Accepted |
| 002 | Organization context for RLS | Multi-tenancy | ✅ Accepted |
| 003 | Service role for backend | Access control | ✅ Accepted |
| 004 | JSONB for flexible data | Schema design | ✅ Accepted |
| 005 | Enum types | Type safety | ✅ Accepted |
| 006 | Migration by release | Migration management | ✅ Accepted |
| 007 | Supabase Storage for files | File storage | ✅ Accepted |
| 008 | Realtime via WebSockets | Real-time updates | ✅ Accepted |
| 009 | Clerk for authentication | Auth provider | ✅ Accepted |
| 010 | TypeScript type generation | Frontend types | ✅ Accepted |
| 011 | Composite indexes | Performance | ✅ Accepted |
| 012 | Soft deletes | Data deletion | 🔄 Proposed |

---

## Review Schedule

These ADRs should be reviewed:
- **Quarterly**: ADRs 001, 002, 003, 006, 011 (platform and infrastructure decisions)
- **Annually**: All ADRs
- **On major changes**: Related ADRs when significant changes are made

**Last Review**: June 14, 2026  
**Next Review**: September 14, 2026

---

## How to Add a New ADR

1. **Create a new section** at the end of this file
2. **Use the template**:
   ```markdown
   ## ADR-XXX: Title

   **Date**: YYYY-MM-DD  
   **Status**: Proposed/Accepted/Rejected/Deprecated  
   **Context**: Brief context

   ### Problem
   Description of the problem

   ### Decision
   What was decided

   ### Consequences
   
   #### Positive
   - ✅ Benefits
   
   #### Negative
   - ⚠️ Drawbacks
   
   ### Alternatives Considered
   - Alternative 1
   - Alternative 2
   
   ### Implementation
   Code examples, SQL, etc.
   ```
3. **Update the summary table** at the bottom
4. **Set review date** (typically 3-12 months in the future)
5. **Submit for review** to the team

---

*Inspired by [MADR](https://adr.github.io/madr/) (Markdown Architectural Decision Records)*
