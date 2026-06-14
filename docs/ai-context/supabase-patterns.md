# Supabase Patterns - selltonai-database/supabase

## Overview

The selltonai-database/supabase project uses **Supabase** (PostgreSQL with superpowers) as the shared database infrastructure. This document covers Supabase-specific patterns, configurations, and best practices used across all Sellton services.

Supabase provides:
- PostgreSQL database with REST API
- Row Level Security (RLS) for multi-tenancy
- Realtime subscriptions via WebSockets
- Authentication (integrated with Clerk)
- Storage for file uploads
- Dashboard and monitoring tools

---

## Supabase CLI Patterns

### Project Initialization

```bash
# Install Supabase CLI globally
npm install -g supabase

# Initialize Supabase project
cd selltonai-database/supabase
supabase init

# Start local Supabase instance
supabase start

# Stop local Supabase
supabase stop
```

### Local Development Workflow

```bash
# 1. Start Supabase
supabase start

# 2. Apply all migrations
supabase db reset

# 3. Generate TypeScript types for frontend
supabase gen types typescript --local > ../../selltonai/src/types/database.ts

# 4. Stop when done
supabase stop
```

### Migration Management

#### Creating New Migrations

```bash
# Create a new migration file
supabase migration new add_new_column_to_table

# This creates: migrations/next-release/{timestamp}_add_new_column_to_table.sql
```

#### Migration File Structure

```sql
-- Migration: Add crm_list_id column to companies table
-- Date: 2026-04-05
-- Author: Developer Name
-- Description: Add crm_list_id foreign key to track CRM import source
-- Affected services: selltonai-modal, selltonai
-- Requires code changes: Yes - update extraction logic
-- Breaking: No

-- SQL changes below this line
ALTER TABLE companies ADD COLUMN crm_list_id uuid;

-- Add foreign key constraint
ALTER TABLE companies 
  ADD CONSTRAINT companies_crm_list_id_fkey 
  FOREIGN KEY (crm_list_id) REFERENCES crm_lists(id);

-- Add comment for documentation
COMMENT ON COLUMN companies.crm_list_id IS 'Reference to the CRM list this company was imported from';

-- Add index for query performance
CREATE INDEX idx_companies_crm_list_id ON companies(crm_list_id) WHERE crm_list_id IS NOT NULL;

-- Add RLS policy (if needed)
CREATE POLICY "Users can view companies by CRM list for their organization"
  ON companies FOR SELECT
  USING (organization_id = current_setting('app.current_org_id', true));
```

#### Migration Lifecycle

```bash
# Apply all migrations
supabase migration up

# Apply specific migration
supabase migration up --name add_new_column_to_table

# Revert migration
supabase migration down

# Reset and reapply all migrations
supabase db reset

# Deploy to remote database
supabase migration up --db-url $SUPABASE_URL
```

### Release Management

Migrations are organized by release:

```
selltonai-database/supabase/migrations/
├── release_1.0.0/         # Initial release
│   ├── 001_create_organizations.sql
│   ├── 002_create_users.sql
│   └── MANIFEST.md
│
├── release_1.0.1/         # Bug fixes
│   ├── 003_fix_user_org_constraint.sql
│   └── MANIFEST.md
│
├── release_1.1.0/         # Feature release
│   ├── 004_add_campaigns_table.sql
│   └── MANIFEST.md
│
├── release_1.2.0/         # Latest release
│   ├── 254_create_linkedin_accounts.sql
│   ├── 255_create_linkedin_action_log.sql
│   └── MANIFEST.md
│
├── next-release/           # Unreleased migrations
│   ├── 999_new_feature.sql
│   └── MANIFEST.md
│
├── COMPLETE_DATABASE_SETUP_1.0.0.sql  # Full schema dump
└── full_schema.sql        # Current full schema
```

**MANIFEST.md Template**:
```markdown
# Release X.Y.Z Migration Manifest

## Migrations
- 001_create_table_x.sql - Description
- 002_add_column_y.sql - Description

## Dependencies
- Requires release X.Y.Z-1 to be applied first

## Breaking Changes
- None

## Notes
- Additional context for deployment
```

---

## Row Level Security (RLS) Patterns

### Standard RLS Policy Pattern

All public tables have RLS enabled with organization-based filtering:

```sql
-- 1. Enable RLS on the table
ALTER TABLE table_name ENABLE ROW LEVEL SECURITY;

-- 2. Create SELECT policy (most common)
CREATE POLICY "Users can view data for their organization"
  ON table_name FOR SELECT
  USING (organization_id = current_setting('app.current_org_id', true));

-- 3. Create INSERT policy
CREATE POLICY "Users can insert data for their organization"
  ON table_name FOR INSERT
  WITH CHECK (organization_id = current_setting('app.current_org_id', true));

-- 4. Create UPDATE policy
CREATE POLICY "Users can update data for their organization"
  ON table_name FOR UPDATE
  USING (organization_id = current_setting('app.current_org_id', true));

-- 5. Create DELETE policy
CREATE POLICY "Users can delete data for their organization"
  ON table_name FOR DELETE
  USING (organization_id = current_setting('app.current_org_id', true));
```

### Special RLS Patterns

#### User Profile Access

Users can view and update their own profile:

```sql
-- Users can view their own profile
CREATE POLICY "Users can view own profile"
  ON users FOR SELECT
  USING (id = auth.uid());

-- Users can update their own profile
CREATE POLICY "Users can update own profile"
  ON users FOR UPDATE
  USING (id = auth.uid());

-- Admins can view users in their organization
CREATE POLICY "Admins can view organization users"
  ON users FOR SELECT
  USING (
    id = auth.uid() OR
    EXISTS (
      SELECT 1 FROM user_organizations 
      WHERE user_id = id 
      AND organization_id = current_setting('app.current_org_id', true)
    )
  );
```

#### Organization Settings

Only one row per organization, strict access control:

```sql
CREATE POLICY "Organization can view its settings"
  ON organization_settings FOR SELECT
  USING (organization_id = current_setting('app.current_org_id', true));

CREATE POLICY "Organization can update its settings"
  ON organization_settings FOR UPDATE
  USING (organization_id = current_setting('app.current_org_id', true));

CREATE POLICY "Prevent organization_settings insert if exists"
  ON organization_settings FOR INSERT
  WITH CHECK (
    organization_id = current_setting('app.current_org_id', true) AND
    NOT EXISTS (
      SELECT 1 FROM organization_settings 
      WHERE organization_id = current_setting('app.current_org_id', true)
    )
  );
```

#### Public Read Tables

Some tables may allow public read access:

```sql
-- Allow public read access (use with caution)
CREATE POLICY "Public read access"
  ON public_table FOR SELECT
  USING (true);
```

### RLS Context Setting

Frontend services must set the organization context before queries:

**TypeScript (selltonai)**:
```typescript
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
  import.meta.env.VITE_SUPABASE_URL,
  import.meta.env.VITE_SUPABASE_ANON_KEY
);

// Set current organization context
export async function setOrganization(orgId: string) {
  const { error } = await supabase.rpc('set_current_org_id', {
    org_id: orgId
  });
  
  if (error) {
    console.error('Failed to set organization:', error);
    throw error;
  }
}
```

**Python (selltonai-modal)**:
```python
from supabase import create_client

supabase = create_client(supabase_url, supabase_key)

# Set organization context
def set_organization(org_id: str):
    result = supabase.rpc('set_current_org_id', {'org_id': org_id}).execute()
    if result.error:
        raise Exception(f"Failed to set org: {result.error}")
    return result.data
```

### RLS Custom Function

The `set_current_org_id` RPC function:

```sql
CREATE OR REPLACE FUNCTION public.set_current_org_id(org_id text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  PERFORM set_config('app.current_org_id', org_id, true);
  RETURN org_id;
END;
$$;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION public.set_current_org_id TO anon, authenticated;
```

---

## Storage Patterns

### Bucket Structure

```
Supabase Storage
├── organization_files/      # Document uploads
│   ├── org_{org_id}/
│   │   ├── {file_id}.pdf
│   │   ├── {file_id}.docx
│   │   └── ...
│   └── ...
│
├── avatars/                # User profile pictures
│   └── {user_id}.jpg
│
└── temp/                   # Temporary files
    └── {session_id}/
```

### File Upload

**TypeScript**:
```typescript
const { data, error } = await supabase
  .storage
  .from('organization_files')
  .upload(`org_${organizationId}/${fileId}.pdf`, file, {
    cacheControl: '3600',
    upsert: false,
    contentType: 'application/pdf'
  });
```

**Python**:
```python
from supabase import create_client

supabase = create_client(supabase_url, supabase_key)

with open(file_path, 'rb') as f:
    result = supabase.storage.from_('organization_files').upload(
        f'org_{organization_id}/{file_id}.pdf',
        f,
        file_options={'content-type': 'application/pdf'}
    ).execute()
```

### File Download

```typescript
const { data, error } = await supabase
  .storage
  .from('organization_files')
  .download(`org_${organizationId}/${fileId}.pdf`);

// Get public URL
const { data: { publicUrl } } = supabase
  .storage
  .from('organization_files')
  .getPublicUrl(`org_${organizationId}/${fileId}.pdf`);
```

### File List with Prefix

```typescript
const { data, error } = await supabase
  .storage
  .from('organization_files')
  .list(`org_${organizationId}/`, {
    limit: 100,
    offset: 0,
    sortBy: { column: 'created_at', order: 'desc' }
  });
```

---

## Realtime Patterns

### Subscription Setup

**TypeScript**:
```typescript
const channel = supabase
  .channel(`org_${organizationId}_changes`)
  .on(
    'postgres_changes',
    {
      event: '*',
      schema: 'public',
      table: 'campaigns',
      filter: `organization_id=eq.${organizationId}`
    },
    (payload) => {
      console.log('Campaign changed:', payload.new);
      // Update local state
    }
  )
  .subscribe();

// Later, unsubscribe
supabase.removeChannel(channel);
```

### Broadcast Messages

Services can broadcast custom messages to all subscribers:

**Sending**:
```typescript
const channel = supabase.channel('refresh_cache');
channel.send({
  type: 'broadcast',
  event: 'invalidate_campaigns',
  payload: { organization_id: orgId }
});
```

**Receiving**:
```typescript
const channel = supabase
  .channel('refresh_cache')
  .on('broadcast', { event: 'invalidate_campaigns' }, (payload) => {
    console.log('Invalidate cache:', payload);
    // Refresh local cache
  })
  .subscribe();
```

### Realtime Best Practices

1. **Use organization-scoped channels**: `org_{org_id}_table`
2. **Filter by organization_id**: Always include in filter
3. **Clean up subscriptions**: Remove channels when component unmounts
4. **Handle errors**: Implement error handlers for subscription failures
5. **Reconnect logic**: Handle connection drops gracefully

```typescript
// Reconnection handling
supabase.channel('db_changes').on('error', (error) => {
  console.error('Realtime error:', error);
  // Attempt to reconnect
  setTimeout(() => {
    subscribeToChanges();
  }, 5000);
});
```

---

## Query Patterns

### REST API Best Practices

#### Select with Filters

```typescript
// Basic select
const { data, error } = await supabase
  .from('campaigns')
  .select('id, name, status, created_at')
  .eq('organization_id', orgId)
  .order('created_at', { ascending: false })
  .limit(50);

// With multiple filters
const { data, error } = await supabase
  .from('companies')
  .select('*')
  .eq('organization_id', orgId)
  .eq('processing_status', 'processed')
  .gt('icp_score->>score', 70)
  .order('icp_score->>score', { ascending: false })
  .limit(20);
```

#### Insert with Return

```typescript
// Insert single record
const { data, error } = await supabase
  .from('campaigns')
  .insert({
    organization_id: orgId,
    name: 'New Campaign',
    status: 'draft'
  })
  .select()
  .single();

// Bulk insert
const { data, error } = await supabase
  .from('companies')
  .insert(companiesArray)
  .select();
```

#### Update with Conditions

```typescript
// Update specific record
const { data, error } = await supabase
  .from('campaigns')
  .update({ status: 'active' })
  .eq('id', campaignId)
  .eq('organization_id', orgId)
  .select();

// Bulk update
const { data, error } = await supabase
  .from('tasks')
  .update({ status: 'completed' })
  .eq('organization_id', orgId)
  .in('id', taskIds);
```

#### Upsert Pattern

```typescript
const { data, error } = await supabase
  .from('organization_settings')
  .upsert({
    organization_id: orgId,
    settings: { theme: 'dark' }
  })
  .select();
```

### RPC (Remote Procedure Calls)

#### Calling Stored Procedures

```typescript
// Simple RPC
const { data, error } = await supabase.rpc('get_organization_stats', {
  org_id: orgId
});

// RPC with multiple parameters
const { data, error } = await supabase.rpc('search_companies', {
  org_id: orgId,
  query: searchTerm,
  limit: 10
});
```

#### Custom RPC Functions

**PostgreSQL Function**:
```sql
CREATE OR REPLACE FUNCTION public.get_organization_stats(org_id text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  result json;
BEGIN
  SELECT json_build_object(
    'total_campaigns', (SELECT count(*) FROM campaigns WHERE organization_id = org_id),
    'total_companies', (SELECT count(*) FROM companies WHERE organization_id = org_id),
    'total_contacts', (SELECT count(*) FROM contacts WHERE organization_id = org_id),
    'active_campaigns', (SELECT count(*) FROM campaigns 
                         WHERE organization_id = org_id AND status = 'active')
  ) INTO result;
  
  RETURN result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_organization_stats TO anon, authenticated;
```

**TypeScript Usage**:
```typescript
const { data } = await supabase.rpc('get_organization_stats', { org_id: orgId });
// data = { total_campaigns: 5, total_companies: 250, ... }
```

### JSONB Query Patterns

#### Query JSONB Fields

```typescript
// Filter by nested JSONB value
const { data, error } = await supabase
  .from('companies')
  .select('*')
  .eq('organization_id', orgId)
  .gt('icp_score->>grade', 'B')
  .order('icp_score->>score', { ascending: false });

// Check if JSONB contains value
const { data, error } = await supabase
  .from('companies')
  .select('*')
  .eq('organization_id', orgId)
  .contains('b2b_enrichment', { industry: 'SaaS' });
```

#### Update JSONB Fields

```typescript
// Update nested JSONB value
const { data, error } = await supabase
  .from('companies')
  .update({
    'icp_score': { ...icpScore, grade: 'A' }
  })
  .eq('id', companyId);

// Append to JSONB array
const { data, error } = await supabase
  .from('companies')
  .update({
    'b2b_enrichment': {
      ...existingEnrichment,
      tags: [...(existingEnrichment.tags || []), 'new-tag']
    }
  })
  .eq('id', companyId);
```

---

## Indexing Patterns

### Standard Indexes

```sql
-- Single column index
CREATE INDEX idx_table_name_column ON table_name(column);

-- Composite index (most common for organization-scoped queries)
CREATE INDEX idx_table_name_org_status ON table_name(organization_id, status);

-- Unique index
CREATE UNIQUE INDEX idx_table_name_unique_column ON table_name(unique_column);
```

### Partial Indexes

```sql
-- Index only active records
CREATE INDEX idx_campaigns_org_active ON campaigns(organization_id) 
  WHERE status = 'active';

-- Index only non-null values
CREATE INDEX idx_companies_crm_list_id ON companies(crm_list_id) 
  WHERE crm_list_id IS NOT NULL;
```

### JSONB Indexes

```sql
-- GIN index for JSONB queries
CREATE INDEX idx_companies_icp_score_gin ON companies USING GIN (icp_score);

-- GIN index for JSONB array
CREATE INDEX idx_companies_tags_gin ON companies USING GIN (b2b_enrichment->'tags');
```

### Index Naming Convention

| Table | Column(s) | Index Name |
|-------|-----------|------------|
| campaigns | organization_id | idx_campaigns_organization_id |
| campaigns | (organization_id, status) | idx_campaigns_org_status |
| companies | organization_id | idx_companies_organization_id |
| companies | processing_status | idx_companies_processing_status |
| companies | crm_list_id | idx_companies_crm_list_id |

---

## Enum Patterns

### Custom Enum Types

```sql
-- Define enum type
CREATE TYPE company_processing_status AS ENUM (
  'scheduled',
  'processing',
  'processed',
  'failed',
  'blocked_by_icp',
  'imported'
);

-- Use in table
ALTER TABLE companies ADD COLUMN processing_status company_processing_status 
  DEFAULT 'scheduled';

-- Add comment
COMMENT ON TYPE company_processing_status IS 'Company processing state';
COMMENT ON COLUMN companies.processing_status IS 'Current processing status of the company';
```

### Adding New Enum Values

```sql
-- Add new value to existing enum
ALTER TYPE company_processing_status ADD VALUE 'new_status';

-- This is a non-breaking change for existing data
-- But requires application code updates to handle new value
```

### Current Enum Types

| Type | Values | Used In |
|------|--------|---------|
| company_processing_status | scheduled, processing, processed, failed, blocked_by_icp, imported | companies |
| pipeline_stage | prospect, appointment_requested, qualified, proposal, negotiation, won, lost, not_interested | contacts |
| task_type | company_verification, email_copy, call_script, follow_up_email | tasks |
| task_status | pending, approved, rejected, completed, cancelled | tasks |
| email_search_status | search_not_started, searching, finished_searching_email | contacts |
| import_status | raw, extracted, failed | crm_raw_records |
| record_type | unknown, company, person | crm_raw_records |
| campaign_status | draft, active, paused, completed | campaigns |

---

## Performance Patterns

### Query Optimization

**Do**:
```typescript
// Use indexed columns in WHERE
const { data } = await supabase
  .from('companies')
  .select('id, name')
  .eq('organization_id', orgId)
  .eq('processing_status', 'processed')
  .limit(100);
```

**Don't**:
```typescript
// Full table scan (slow)
const { data } = await supabase
  .from('companies')
  .select('*')
  .limit(100);
```

### Pagination

```typescript
// Page-based pagination
const page = 1;
const pageSize = 50;

const { data, count } = await supabase
  .from('companies')
  .select('*', { count: 'exact' })
  .eq('organization_id', orgId)
  .order('created_at', { ascending: false })
  .limit(pageSize)
  .range((page - 1) * pageSize, page * pageSize - 1);

// totalPages = Math.ceil(count / pageSize)
```

### Batch Operations

```typescript
// Process in batches to avoid timeouts
const batchSize = 100;

for (let i = 0; i < allIds.length; i += batchSize) {
  const batch = allIds.slice(i, i + batchSize);
  
  const { data, error } = await supabase
    .from('companies')
    .update({ status: 'updated' })
    .in('id', batch);
  
  await new Promise(resolve => setTimeout(resolve, 100)); // Rate limiting
}
```

---

## Error Handling Patterns

### Standard Error Handling

```typescript
const { data, error } = await supabase
  .from('campaigns')
  .select('*')
  .eq('organization_id', orgId);

if (error) {
  // Handle RLS violation (42501)
  if (error.code === '42501') {
    console.error('RLS violation: Check organization context');
    // Set org context and retry
    await setOrganization(orgId);
    return retryQuery();
  }
  
  // Handle rate limiting (429)
  if (error.code === '429') {
    await new Promise(resolve => setTimeout(resolve, 1000));
    return retryQuery();
  }
  
  // Re-throw for unexpected errors
  throw error;
}
```

### Common Error Codes

| Code | Error | Solution |
|------|-------|----------|
| 42501 | RLS Violation | Check org context, verify filters |
| 400 | Bad Request | Check query syntax |
| 401 | Unauthorized | Check API key |
| 403 | Forbidden | Check permissions |
| 404 | Not Found | Check table/column names |
| 408 | Request Timeout | Increase timeout, optimize query |
| 429 | Too Many Requests | Implement backoff, reduce batch size |
| 500 | Internal Server Error | Check database logs |
| 503 | Service Unavailable | Retry with exponential backoff |

---

## Backup & Recovery Patterns

### Manual Backup

```bash
# Export database
pg_dump -h db.xxx.supabase.co -U postgres -d postgres \
  -Fc -b -v -f backup/full_schema_$(date +%Y%m%d_%H%M%S).sql

# Export as plain SQL
pg_dump -h db.xxx.supabase.co -U postgres -d postgres \
  -f backup/full_schema_$(date +%Y%m%d).plain.sql
```

### Restore Process

```bash
# Restore from backup
psql -h db.xxx.supabase.co -U postgres -d postgres \
  -f backup/full_schema_YYYYMMDD.sql

# Or using Supabase CLI
supabase db reset --db-url $SUPABASE_URL
```

### Automated Backup Script

**File**: `scripts/backup.sh`

```bash
#!/bin/bash

# Configuration
SUPABASE_URL="https://xxx.supabase.co"
SUPABASE_DB="postgres"
BACKUP_DIR="./backup"
RETENTION_DAYS=30

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Export database
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
pg_dump -h "$SUPABASE_URL" -U postgres -d "$SUPABASE_DB" \
  -Fc -b -v -f "$BACKUP_DIR/full_schema_$TIMESTAMP.sql" \
  --no-password

# Clean up old backups
find "$BACKUP_DIR" -name "*.sql" -mtime +$RETENTION_DAYS -delete

echo "Backup completed: $BACKUP_DIR/full_schema_$TIMESTAMP.sql"
```

---

## Configuration Patterns

### config.toml

**File**: `config.toml`

```toml
[global]
project_id = "selltonai"

[api]
port = 54321

[db]
port = 54322
major_version = 15

[studio]
port = 54323

[auth]
site_url = "http://localhost:3000"
jwt_secret = "super-secret-jwt-secret"

[inbucket]
enabled = true

[realtime]
enabled = true
```

### Environment Variables

```bash
# Required for all services
SUPABASE_URL=https://xxx.supabase.co
SUPABASE_ANON_KEY=eyJ...  # For frontend
SUPABASE_SERVICE_ROLE_KEY=eyJ...  # For backend

# Local development
SUPABASE_LOCAL_URL=http://localhost:54321
SUPABASE_LOCAL_ANON_KEY=eyJ...
SUPABASE_LOCAL_SERVICE_KEY=eyJ...

# Debugging
SUPABASE_LOG_LEVEL=debug
SUPABASE_DB_LOG_LEVEL=debug
```

---

## Testing Patterns

### Local Testing Setup

```bash
# Start local Supabase
supabase start

# Apply migrations
supabase db reset

# Seed test data
psql -h localhost -p 54322 -U postgres -d postgres -f seed.sql
```

### Test Data Seeding

**File**: `seed.sql`

```sql
-- Create test organization
INSERT INTO organizations (id, name) 
VALUES ('test_org_001', 'Test Organization')
ON CONFLICT (id) DO NOTHING;

-- Create test user
INSERT INTO users (id, email, firstname, lastname) 
VALUES ('test_user_001', 'test@example.com', 'Test', 'User')
ON CONFLICT (id) DO NOTHING;

-- Link user to organization
INSERT INTO user_organizations (user_id, organization_id, role) 
VALUES ('test_user_001', 'test_org_001', 'admin')
ON CONFLICT (user_id, organization_id) DO NOTHING;

-- Create test campaign
INSERT INTO campaigns (id, organization_id, name, status) 
VALUES ('test_campaign_001', 'test_org_001', 'Test Campaign', 'draft')
ON CONFLICT (id) DO NOTHING;
```

---

## Security Patterns

### Key Management

| Key Type | Access Level | Used By | Rotation |
|----------|-------------|---------|----------|
| Anon Key | RLS enforced | Frontend services | Easy (no breaking changes) |
| Service Role Key | RLS bypassed | Backend services | Coordinated (update all services) |
| JWT Secret | Token validation | Auth | Managed by Clerk |

**Key Rotation Procedure**:
1. Generate new key in Supabase dashboard
2. Update in `main-secrets` Modal secret
3. Update in all services' environment variables
4. Test all services with new key
5. Remove old key

### SQL Injection Prevention

**Always use parameterized queries**:
```typescript
// ✅ Safe - parameterized
const { data } = await supabase
  .from('users')
  .select('*')
  .eq('email', userEmail);

// ❌ Dangerous - never do this
const { data } = await supabase
  .from('users')
  .select('*')
  .eq('email', `${userInput}`); // Raw string interpolation
```

### Connection Pooling

For backend services (Python):

```python
from supabase import create_client
from psycopg2.pool import SimpleConnectionPool

# Create connection pool
pool = SimpleConnectionPool(
    minconn=1,
    maxconn=10,
    host=db_host,
    database=db_name,
    user=db_user,
    password=db_password
)

# Use pool for queries
def query_db(sql, params):
    conn = pool.getconn()
    try:
        cursor = conn.cursor()
        cursor.execute(sql, params)
        return cursor.fetchall()
    finally:
        pool.putconn(conn)
```

---

## Monitoring & Debugging

### Supabase Dashboard

Access at: `https://app.supabase.com/project/xxx`

**Key Monitoring Tabs**:
- **Tables**: View table structure, data, and RLS policies
- **SQL Editor**: Run ad-hoc queries
- **Authentication**: View users and auth logs
- **Storage**: Browse and manage files
- **Realtime**: View active subscriptions
- **Logs**: View database and API logs
- **Metrics**: CPU, memory, query performance

### Query Logging

Enable query logging in Supabase dashboard:
- Navigate to Settings → Database
- Enable `log_statement` = `all` (development only)
- View logs in Dashboard → Logs

### Performance Analysis

```sql
-- Find slow queries
SELECT query, total_time, calls, mean_time
FROM pg_stat_statements
ORDER BY mean_time DESC
LIMIT 10;

-- Check long-running queries
SELECT pid, now() - query_start AS duration, query
FROM pg_stat_activity
WHERE state = 'active' AND now() - query_start > interval '5 seconds'
ORDER BY duration DESC;

-- Check index usage
SELECT schemaname, relname, indexrelname, idx_scan
FROM pg_stat_user_indexes
ORDER BY idx_scan DESC;
```

---

## Best Practices Summary

### Supabase Best Practices

1. **Always use RLS** for all public tables
2. **Filter by organization_id** in all queries
3. **Use indexes** for frequently queried columns
4. **Enable connection pooling** for backend services
5. **Use parameterized queries** to prevent SQL injection
6. **Batch operations** to reduce API calls
7. **Monitor query performance** regularly
8. **Clean up old backups** to save storage
9. **Test migrations** locally before deploying
10. **Document breaking changes** in migration files

### Project-Specific Best Practices

1. **Migration files**: Always include metadata header
2. **RLS policies**: Use consistent naming convention
3. **Indexes**: Create for all foreign keys and query filters
4. **Enum changes**: Coordinate with all services
5. **Type generation**: Update TypeScript types after schema changes
6. **Backup**: Run automated backups regularly
7. **Local development**: Use Supabase CLI for consistency

---

## Troubleshooting

### Common Issues & Solutions

| Issue | Cause | Solution |
|-------|-------|----------|
| RLS violation (42501) | Organization context not set | Call `set_current_org_id()` before queries |
| Connection refused | Supabase not running | Run `supabase start` |
| Migration errors | Syntax error in SQL | Check migration file syntax |
| Type errors | Schema changed, types not updated | Run `supabase gen types` |
| Rate limiting (429) | Too many requests | Implement backoff, reduce batch size |
| Timeout errors | Query too slow | Optimize query, add indexes |
| Missing data | RLS filtering too restrictive | Check RLS policies |
| Storage upload fails | Bucket doesn't exist | Create bucket in Supabase dashboard |

### Debug Commands

```bash
# View Supabase logs
supabase logs

# Check running containers
supabase status

# View migration status
supabase migration list

# Test connection
psql -h localhost -p 54322 -U postgres -d postgres

# Reset database
supabase db reset
```

### Useful SQL Queries

```sql
-- Check all tables with RLS disabled
SELECT schemaname, tablename
FROM pg_tables
WHERE schemaname = 'public'
AND NOT EXISTS (
  SELECT 1 FROM pg_policies 
  WHERE schemaname = pg_tables.schemaname 
  AND tablename = pg_tables.tablename
);

-- Check all tables without organization_id column
SELECT table_name
FROM information_schema.columns
WHERE table_schema = 'public'
AND column_name = 'organization_id'
GROUP BY table_name;

-- Find missing indexes
SELECT schemaname, tablename, attname
FROM pg_stat_user_indexes
WHERE idx_scan < 10
AND schemaname = 'public';
```
