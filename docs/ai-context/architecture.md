# System Architecture - Supabase

## Overview

**selltonai-database/supabase** is the shared database infrastructure project for the Sellton B2B sales platform. It manages the PostgreSQL database schema, migrations, Row Level Security (RLS) policies, and Supabase configuration that all Sellton services depend on.

This project serves as the **source of truth** for:
- Database schema definitions
- Migration history and new migrations
- RLS policy configurations
- Table ownership and access patterns
- Cross-service data contracts

## System Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        SELLTON PLATFORM DATABASE LAYER                         │
└─────────────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                            SUPABASE INFRASTRUCTURE                            │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │                     PostgreSQL Database (v15)                        │  │
│  │                                                                     │  │
│  │  ┌─────────────────────────────────────────────────────────────┐    │  │
│  │  │                         SCHEMAS                               │    │  │
│  │  │                                                             │    │  │
│  │  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐        │    │  │
│  │  │  │  public       │  │  auth         │  │  storage     │        │    │  │
│  │  │  │  (RLS enabled)│  │  (Clerk sync)│  │  (file store)│        │    │  │
│  │  │  │               │  │               │  │              │        │    │  │
│  │  │  │ - organizations│  │ - users      │  │ - buckets   │        │    │  │
│  │  │  │ - campaigns   │  │ - audits     │  │ - objects   │        │    │  │
│  │  │  │ - companies   │  │              │  │              │        │    │  │
│  │  │  │ - contacts    │  │              │  │              │        │    │  │
│  │  │  │ - tasks       │  │              │  │              │        │    │  │
│  │  │  │ - onboarding_ │  │              │  │              │        │    │  │
│  │  │  │   research    │  │              │  │              │        │    │  │
│  │  │  │ - ... 30+    │  │              │  │              │        │    │  │
│  │  │  │   tables      │  │              │  │              │        │    │  │
│  │  │  └──────────────┘  └──────────────┘  └──────────────┘        │    │  │
│  │  │                                                             │    │  │
│  │  └─────────────────────────────────────────────────────────────┘    │  │
│  │                                                                     │  │
│  │  ┌─────────────────────────────────────────────────────────────┐    │  │
│  │  │                      RLS POLICIES                            │    │  │
│  │  │                                                             │    │  │
│  │  │  USING (organization_id = current_setting('app.current_org_id')) │    │  │
│  │  │  FOR SELECT, INSERT, UPDATE, DELETE ON ALL TABLES             │    │  │
│  │  │                                                             │    │  │
│  │  └─────────────────────────────────────────────────────────────┘    │  │
│  │                                                                     │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐  │
│  │                         SUPABASE SERVICES                            │  │
│  │                                                                     │  │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐        │  │
│  │  │ REST API │  │ Auth     │  │ Storage  │  │ Realtime │        │  │
│  │  │ (Anon)   │  │ (Clerk)  │  │          │  │ (Websock)│        │  │
│  │  └──────────┘  └──────────┘  └──────────┘  └──────────┘        │  │
│  │                                                                     │  │
│  └─────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                                  │
        ┌─────────────────────────┼─────────────────────────┐
        │                         │                         │
        ▼                         ▼                         ▼
┌──────────────────────┐   ┌──────────────────────┐   ┌──────────────────────┐
│  selltonai (Next.js)  │   │ selltonai-modal      │   │  backoffice           │
│  Frontend            │   │ Backend (Python)     │   │ (AdonisJS)           │
│ - Anon Key           │   │ - Service Role Key   │   │ - Service Role Key   │
│ - RLS Enforced       │   │ - RLS Bypassed       │   │ - RLS Bypassed       │
└──────────────────────┘   └──────────────────────┘   └──────────────────────┘
        │                         │                         │
        ▼                         ▼                         ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                            DATA FLOW                                        │
│                                                                             │
│  selltonai (Frontend)                                                       │
│    ↓ HTTP requests (RLS enforced via anon key)                              │
│  Supabase REST API                                                          │
│    ↓ PostgreSQL queries                                                      │
│  PostgreSQL Database                                                         │
│    ↓ Returns filtered data                                                   │
│                                                                             │
│  selltonai-modal (Backend)                                                  │
│    ↓ HTTP requests (RLS bypassed via service role)                          │
│  Supabase REST API                                                          │
│    ↓ PostgreSQL queries (full access)                                        │
│  PostgreSQL Database                                                         │
│    ↓ Returns all data for org                                                │
│                                                                             │
│  Realtime updates via WebSockets:                                           │
│  Supabase Realtime → All clients (filtered by RLS)                           │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Project Structure

```
selltonai-database/supabase/
├── .agents/                   # AI agent configurations
├── .git/                      # Git repository
├── .gitignore                 # Git ignore patterns
├── AGENTS.md                  # Project AI agent guide
├── backup/                    # Database backups
│   └── full_schema_YYYYMMDD.sql
├── config.toml                # Supabase CLI configuration
├── docs/
│   ├── ai-context/            # Internal technical documentation (THIS DIRECTORY)
│   │   ├── architecture.md    # System architecture
│   │   ├── data-models.md      # Database schema & models
│   │   ├── api-contracts.md    # API & service contracts
│   │   ├── supabase-patterns.md # Supabase-specific patterns
│   │   └── decisions.md        # Architecture Decision Records
│   │
│   └── cross-project/          # External service contracts
│       └── README.md           # Table ownership, RLS, migration conventions
│
├── migrations/                # Database migration files
│   ├── release_1.0.0/         # First release
│   │   ├── 001_create_organizations.sql
│   │   ├── 002_create_users.sql
│   │   └── ...
│   │
│   ├── release_1.0.1/         # Bug fixes and improvements
│   ├── release_1.0.2/
│   ├── release_1.0.3/
│   ├── release_1.0.4/
│   ├── release_1.0.5/
│   ├── release_1.1.0/         # Feature release
│   ├── release_1.1.1/
│   ├── release_1.1.2/
│   ├── release_1.2.0/         # Latest release
│   │   ├── 254_create_linkedin_accounts.sql
│   │   ├── 255_create_linkedin_action_log.sql
│   │   └── ...
│   │
│   ├── COMPLETE_DATABASE_SETUP_1.0.0.sql  # Full schema dump
│   ├── full_schema.sql        # Current full schema
│   └── next-release/           # Unreleased migrations
│       ├── 999_new_feature.sql
│       └── MANIFEST.md         # Migration manifest
│
├── operations/                # Checked-in operational infrastructure
│   └── hetzner-production-live-sync/ # Temporary cloud-to-Hetzner PostgreSQL/Storage mirror and cutover
│
├── node_modules/              # npm dependencies
├── package.json               # Dependencies and scripts
├── README.md                  # Project documentation
├── scripts/                   # Utility scripts
│   └── ...
├── seed.sql                   # Database seed data
└── .temp/                     # Temporary files
```

## Database Schema Architecture

### Core Schema Design Principles

1. **Tenant Isolation**: All tables include `organization_id` column
2. **RLS by Default**: All public tables have RLS enabled
3. **JSONB for Flexibility**: Enrichment data stored in JSONB columns
4. **Timestamps**: All tables have `created_at` and `updated_at`
5. **Soft Deletes**: Consider `deleted_at` for important tables
6. **Composite Indexes**: Indexes on frequently queried column combinations
7. **Enum Types**: Custom types for constrained values

### Table Categorization

#### Organization & User Tables
- `organizations` - Top-level tenant
- `users` - User accounts
- `user_organizations` - User-org membership
- `organization_settings` - Per-org configuration
- `organization_onboarding_events` - Onboarding funnel tracking

#### Campaign & Company Tables
- `campaigns` - Sales campaigns
- `campaign_companies` - Campaign-company relationship
- `campaign_seed_companies` - Seed companies for lookalikes
- `companies` - Company records
- `company_contacts` - Company-contact junction

#### Contact & Task Tables
- `contacts` - Person/contact records
- `tasks` - Verification and action tasks
- `campaign_contacts` - Campaign-contact relationship
- `crm_list_members` - Manual CRM list memberships

#### CRM Import Tables
- `crm_lists` - CRM import lists
- `crm_raw_records` - Raw CSV data before processing
- `crm_import_jobs` - Durable progress tracking for large imports

#### Document & Email Tables
- `organization_files` - Uploaded documents
- `organization_files_chunks` - Document chunks for vector embeddings
- `email_accounts` - Gmail OAuth tokens
- `email_tokens` - Email token tracking
- `unmatched_replies` - Incoming emails that couldn't be matched

#### Billing Tables
- `billing_customers` - Billing configuration per organization
- `billing_invoices` - Usage invoices
- `billing_invoice_sequences` - Invoice number sequencing
- `usage` - Billable usage tracking

#### AI & Research Tables
- `onboarding_research` - Onboarding research state
- `sender_voice` - User voice distillation results
- `avatar_interviews` - Retell call tracking
- `style_guidelines` - Writing style guidelines
- `deep_research_settings` - Research provider configuration
- `ai_ark_enrollment_runs` - AI Ark idempotency ledger

#### LinkedIn Integration Tables
- `linkedin_accounts` - LinkedIn account connections
- `linkedin_action_log` - LinkedIn action history
- `linkedin_threads` - LinkedIn conversation threads
- `linkedin_messages` - LinkedIn messages
- `provider_event_log` - Provider event tracking

### Cross-Reference Architecture

For complete table details and ownership matrix, see:
- [Cross-Project Documentation](docs/cross-project/README.md)

## Migration System

### Migration Conventions

#### File Naming
```
{number}_{description}.sql
```

Examples:
- `001_create_organizations.sql`
- `232_add_crm_list_id_column.sql`
- `300_create_onboarding_research.sql`

#### Migration Template
```sql
-- Migration: Description of what this migration does
-- Date: YYYY-MM-DD
-- Author: Developer Name
-- Description: Detailed description of changes
-- Affected services: selltonai, selltonai-modal, backoffice, etc.
-- Requires code changes: Yes/No - if application code must be updated together
-- Breaking: Yes/No - if this is a breaking change

-- SQL changes below this line
ALTER TABLE table_name ADD COLUMN column_name type;

-- Add comment for documentation
COMMENT ON COLUMN table_name.column_name IS 'Description of column purpose';

-- Add indexes for performance
CREATE INDEX idx_table_name_column ON table_name(column_name);

-- For RLS policies
CREATE POLICY "policy_name"
  ON table_name FOR SELECT
  USING (organization_id = current_setting('app.current_org_id', true));
```

### Release Organization

Migrations are grouped into releases:
- `release_X.Y.Z/` - Released migrations
- `next-release/` - Unreleased migrations (staging)

Each release has a MANIFEST.md file documenting:
- All migrations in the release
- Order of application
- Dependencies between migrations
- Breaking changes

### Migration Workflow

1. **Create Migration**
   ```bash
   cd selltonai-database/supabase
   supabase migration new migration_name
   ```

2. **Write SQL** in the generated migration file

3. **Test Locally**
   ```bash
   supabase db reset  # Reset and apply all migrations
   # or
   supabase migration up  # Apply specific migration
   ```

4. **Update MANIFEST.md** with migration details

5. **Move to release folder** when ready to deploy

6. **Deploy to production**
   ```bash
   supabase migration up --db-url $SUPABASE_URL
   ```

## Row Level Security (RLS)

### RLS Policy Pattern

All tables in the public schema enforce RLS with the following pattern:

```sql
-- Enable RLS on table
ALTER TABLE table_name ENABLE ROW LEVEL SECURITY;

-- Select policy: Users can only view their organization's data
CREATE POLICY "Users can view data for their organization"
  ON table_name FOR SELECT
  USING (organization_id = current_setting('app.current_org_id', true));

-- Insert policy: Users can only insert data for their organization
CREATE POLICY "Users can insert data for their organization"
  ON table_name FOR INSERT
  WITH CHECK (organization_id = current_setting('app.current_org_id', true));

-- Update policy: Users can only update their organization's data
CREATE POLICY "Users can update data for their organization"
  ON table_name FOR UPDATE
  USING (organization_id = current_setting('app.current_org_id', true));

-- Delete policy: Users can only delete their organization's data
CREATE POLICY "Users can delete data for their organization"
  ON table_name FOR DELETE
  USING (organization_id = current_setting('app.current_org_id', true));
```

### RLS Context

The `app.current_org_id` setting is set by services based on the user's context:

```typescript
// In selltonai-modal (Python)
supabase_client = create_client(supabase_url, supabase_key)
supabase_client.postgrest.rpc("set_current_org_id", {"org_id": organization_id})

// In selltonai (TypeScript)
const { data, error } = await supabase.rpc('set_current_org_id', {
  org_id: currentOrgId
});
```

### Service Role Key

Backend services (selltonai-modal, backoffice) use the **service role key** which:
- Bypasses all RLS policies
- Has full read/write access
- Used for admin operations and data processing

Frontend services (selltonai, sellton-onboard) use the **anon key** which:
- Enforces all RLS policies
- Only accesses data for the current organization
- Used for user-facing operations

## Service Access Patterns

### Access Matrix

| Service | Access Method | Key Used | RLS Enforced |
|---------|---------------|----------|--------------|
| selltonai | Supabase client | Anon key | ✅ Yes |
| selltonai-modal | Supabase client | Service role | ❌ No (bypassed) |
| backoffice | Supabase client | Service role | ❌ No (bypassed) |
| selltonai-crawler | Supabase client | Service role | ❌ No (bypassed) |
| selltonai-onboard | Supabase client | Anon key | ✅ Yes |

### Authentication Flow

```
Frontend (selltonai) → Clerk (Auth) → JWT Token
  ↓
JWT Token passed to Supabase client
  ↓
Supabase validates JWT and extracts user_id
  ↓
User belongs to one or more organizations (via user_organizations)
  ↓
selltonai sets app.current_org_id setting
  ↓
RLS policies filter by organization_id
```

## Indexing Strategy

### Performance Indexes

The database uses a comprehensive indexing strategy:

#### Organization-Scoped Queries
```sql
-- Filter by organization
CREATE INDEX idx_table_name_organization_id ON table_name(organization_id);

-- Compound index for common queries
CREATE INDEX idx_table_name_org_status ON table_name(organization_id, status);

-- Partial index for specific statuses
CREATE INDEX idx_table_name_org_pending ON table_name(organization_id)
  WHERE status = 'pending';
```

#### Common Index Patterns
```sql
-- Campaign listing
CREATE INDEX idx_campaigns_org_id ON campaigns(organization_id);
CREATE INDEX idx_campaigns_status ON campaigns(status);
CREATE INDEX idx_campaigns_created_at ON campaigns(created_at);
CREATE INDEX idx_campaigns_org_status ON campaigns(organization_id, status);

-- Company filtering
CREATE INDEX idx_companies_org_id ON companies(organization_id);
CREATE INDEX idx_companies_processing_status ON companies(processing_status);
CREATE INDEX idx_companies_campaign_id ON companies(campaign_id);
CREATE INDEX idx_companies_crm_list_id ON companies(crm_list_id) WHERE crm_list_id IS NOT NULL;

-- Contact search
CREATE INDEX idx_contacts_org_id ON contacts(organization_id);
CREATE INDEX idx_contacts_email ON contacts(email);
CREATE INDEX idx_contacts_pipeline_stage ON contacts(pipeline_stage);

-- Task management
CREATE INDEX idx_tasks_campaign_id ON tasks(campaign_id) WHERE campaign_id IS NOT NULL;
CREATE INDEX idx_tasks_company_id ON tasks(company_id) WHERE company_id IS NOT NULL;
CREATE INDEX idx_tasks_contact_id ON tasks(contact_id) WHERE contact_id IS NOT NULL;

-- CRM imports
CREATE INDEX idx_crm_raw_records_list_id ON crm_raw_records(list_id);
CREATE INDEX idx_crm_raw_records_org_id ON crm_raw_records(organization_id);
CREATE INDEX idx_crm_raw_records_import_status ON crm_raw_records(import_status);
```

## JSONB Field Strategy

### JSONB Usage Principles

JSONB columns are used for:
1. **Flexible Data**: Data that varies by provider or use case
2. **Nested Structures**: Hierarchical data that's queryable
3. **Evolution**: Data that may change structure over time
4. **Performance**: Indexable columns within JSONB

### Key JSONB Fields

| Table | Column | Purpose | Indexed |
|-------|--------|---------|---------|
| companies | `b2b_result` | Raw B2B API response | ❌ No |
| companies | `b2b_enrichment` | Normalized enrichment data | ❌ No |
| companies | `icp_score` | ICP scoring results | ✅ Yes (GIN) |
| companies | `deep_research` | Deep research v1 results | ❌ No |
| companies | `deep_research_v2` | Deep research v2 results | ❌ No |
| companies | `outreach_strategy` | AI-generated strategy | ❌ No |
| contacts | `location` | Location data | ❌ No |
| contacts | `analysis` | AI analysis of profile | ❌ No |
| onboarding_research | `core_offer` | Core product offering | ❌ No |
| onboarding_research | `value_propositions` | Value propositions | ❌ No |
| onboarding_research | `icp_hypotheses` | ICP hypotheses | ❌ No |

### JSONB Indexes

```sql
-- GIN index for querying within JSONB
CREATE INDEX idx_companies_icp_score_gin ON companies USING GIN (icp_score);

-- Query example
SELECT * FROM companies 
WHERE icp_score->>'grade' = 'A';
```

## Enum Types

### Custom PostgreSQL Enums

| Type | Values | Purpose |
|------|--------|---------|
| `company_processing_status` | scheduled, processing, processed, failed, blocked_by_icp, imported | Company processing state |
| `pipeline_stage` | prospect, appointment_requested, qualified, proposal, negotiation, won, lost, not_interested | Contact pipeline stage |
| `task_type` | company_verification, email_copy, call_script, follow_up_email | Task type |
| `task_status` | pending, approved, rejected, completed, cancelled | Task status |
| `email_search_status` | search_not_started, searching, finished_searching_email | Email search state |
| `import_status` | raw, extracted, failed | CRM import status |
| `record_type` | unknown, company, person | CRM record classification |
| `campaign_status` | draft, active, paused, discovery_completed, completed, fully_completed, cancelled | Campaign status |

### Adding New Enums

```sql
-- Create new enum type
CREATE TYPE new_enum_type AS ENUM (
  'value1',
  'value2',
  'value3'
);

-- Use in table
ALTER TABLE table_name ADD COLUMN column_name new_enum_type;

-- Add comment
COMMENT ON TYPE new_enum_type IS 'Description of enum purpose';
COMMENT ON COLUMN table_name.column_name IS 'Description of column';
```

**Important**: Enum changes require:
1. Migration to add the type
2. Coordination with all services that use the enum
3. Application code updates to handle new values

## Realtime Functionality

### Realtime Configuration

Supabase Realtime provides WebSocket-based realtime updates:

```typescript
// Client-side subscription
const channel = supabase
  .channel(`table_db_changes`)
  .on(
    'postgres_changes',
    {
      event: '*',
      schema: 'public',
      table: 'campaigns',
      filter: `organization_id=eq.${orgId}`
    },
    (payload) => {
      console.log('Campaign changed:', payload.new);
    }
  )
  .subscribe();
```

### Realtime Use Cases

1. **Campaign Status Updates**: Notify users when campaign processing completes
2. **Task Creation**: Show new tasks in realtime
3. **Company Processing**: Update UI as companies are processed
4. **Collaborative Features**: Multi-user updates in backoffice
5. **Onboarding Progress**: Track onboarding state changes

## Backup & Recovery

### Automated Backups

Supabase provides:
- **Daily backups**: Automated on Pro plan
- **Point-in-time recovery**: Available on Pro plan
- **Retention**: 7 days (configurable on Enterprise)

### Manual Backup Scripts

**File**: `scripts/backup.sh` (example)

```bash
#!/bin/bash

# Configuration
SUPABASE_URL="https://xxx.supabase.co"
SUPABASE_DB="postgres"
BACKUP_DIR="./backup"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Export database
pg_dump -h "$SUPABASE_URL" -U postgres -d "$SUPABASE_DB" \
  -Fc -b -v -f "$BACKUP_DIR/full_schema_$TIMESTAMP.sql" \
  --no-password

# Also export as plain SQL
pg_dump -h "$SUPABASE_URL" -U postgres -d "$SUPABASE_DB" \
  -f "$BACKUP_DIR/full_schema_$TIMESTAMP.plain.sql" \
  --no-password

# Clean up old backups (keep last 30 days)
find "$BACKUP_DIR" -name "*.sql" -mtime +30 -delete

echo "Backup completed: $BACKUP_DIR/full_schema_$TIMESTAMP.sql"
```

### Restore Process

```bash
# Restore from backup
psql -h db.xxx.supabase.co -U postgres -d sellton \
  -f backup/full_schema_YYYYMMDD.sql

# Or using Supabase CLI
supabase db reset --db-url $SUPABASE_URL
```

## Development Environment

### Local Supabase Setup

```bash
# Install Supabase CLI
npm install -g supabase

# Start local Supabase
supabase start

# Apply migrations
supabase db reset

# Stop local Supabase
supabase stop
```

### Local Configuration

**File**: `config.toml` (local development)

```toml
[global]
project_id = "selltonai-local"

[api]
port = 54321

[db]
port = 54322

[studio]
port = 54323

[auth]
site_url = "http://localhost:3000"

[inbucket]
enabled = true
```

### Local Development Workflow

1. Start Supabase: `supabase start`
2. Apply migrations: `supabase db reset`
3. Start services (selltonai-modal, etc.)
4. Test changes
5. Create new migrations for schema changes
6. Repeat

## Technology Stack

### Database
- **PostgreSQL 15**: Primary database engine
- **Supabase**: PostgreSQL with superpowers
  - REST API
  - Authentication
  - Storage
  - Realtime
  - Dashboard

### Tools
- **Supabase CLI**: Local development and deployment
- **psql**: PostgreSQL command-line client
- **pg_dump**: Database export
- **pg_restore**: Database import

### Languages
- **SQL**: Primary language for migrations
- **TypeScript**: For utility scripts

## Performance Characteristics

### Query Performance
- **RLS overhead**: ~1-2ms per query (negligible)
- **Indexed queries**: <100ms typical
- **Complex joins**: 100-500ms
- **Full table scans**: Avoid (use indexes)

### Storage
- **Primary data**: ~50-100MB (growing)
- **Attachments**: Variable (stored in Supabase Storage)
- **JSONB fields**: 20-30% of data volume

### Connections
- **Max connections**: 100 (default)
- **Connection pooling**: Recommended for backend services
- **Idle timeout**: 30s (configurable)

## Security Considerations

### Data Isolation
- **RLS**: Enforced for all frontend access
- **Service role**: Only for trusted backend services
- **Organization filtering**: Required in all queries

### SQL Injection Prevention
- **Parameterized queries**: Always use parameterized queries
- **Supabase client**: Automatically parameterizes
- **Raw SQL**: Never concatenate user input

### Sensitive Data
- **Service role key**: Never exposed to frontend
- **Anon key**: Safe to expose (RLS enforced)
- **JWT tokens**: Short-lived, rotated regularly

### Audit Logging
- **Supabase logs**: Available in dashboard
- **Custom audit tables**: For important operations
- **Retention**: 7-30 days (configurable)

## Cross-Project Dependencies

| Project | Dependency Type | Details |
|---------|----------------|---------|
| selltonai | Consumer | Reads all tables via REST API with RLS |
| selltonai-modal | Writer | Full access via service role, writes to most tables |
| backoffice | Admin | Full access via service role, reads all data |
| selltonai-crawler | Writer | Writes enrichment data, updates companies/contacts |
| selltonai-onboard | Writer | Writes user/org data via API, reads onboarding state |
| selltonai-vector-api | Consumer | Reads organization_files and chunks for vector processing |
| selltonai-gmail-api | Writer | Writes email_accounts, email_tokens, unmatched_replies |

For complete dependency details, see:
- [Cross-Project Documentation](docs/cross-project/README.md)
