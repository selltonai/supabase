# Cross-Project Contracts - Supabase

This directory documents how all services interact with Supabase and shared database contracts.

---

## Overview

Supabase (PostgreSQL) is the **shared database** for all Sellton services. This document defines:
- Table ownership (which service writes/reads)
- Shared schema contracts
- Row Level Security rules
- Migration conventions

---

## Service Access Patterns

| Service | Access Type | Key Used | RLS? |
|---------|------------|----------|------|
| **selltonai** (frontend) | Read/Write | Anon key | ✅ Enforced |
| **selltonai-modal** (backend) | Full access | Service role | ❌ Bypasses |
| **backoffice** (admin) | Full access | Service role | ❌ Bypasses |
| **selltonai-crawler** | Write only | Service role | ❌ Bypasses |
| **selltonai-onboard** | Write only | Anon key | ✅ Enforced |

**Critical**: All services must filter by `organization_id` for data isolation.

---

## Table Ownership Matrix

### Core Tables

| Table | Primary Writer | Primary Readers | Purpose |
|-------|---------------|-----------------|---------|
| **organizations** | selltonai-onboard | All | Organization accounts |
| **users** | selltonai-onboard | All | User accounts |
| **user_organizations** | selltonai-onboard | All | User-org membership |
| **organization_settings** | backoffice | All | Per-org settings |

### Campaign & Company Tables

| Table | Primary Writer | Primary Readers | Purpose |
|-------|---------------|-----------------|---------|
| **campaigns** | selltonai-modal | selltonai, backoffice | Campaign management |
| **campaign_companies** | selltonai-modal | selltonai | Campaign-company linking |
| **campaign_seed_companies** | selltonai-modal | selltonai | Seed companies for lookalikes |
| **companies** | selltonai-modal, crawler | selltonai, backoffice | Company records |
| **contacts** | selltonai-modal | selltonai, backoffice | Contact records |
| **company_contacts** | selltonai-modal | selltonai | Company-contact relationships |
| **tasks** | selltonai-modal | selltonai, backoffice | Verification tasks |

### CRM Tables

| Table | Primary Writer | Primary Readers | Purpose |
|-------|---------------|-----------------|---------|
| **crm_lists** | selltonai-modal | selltonai | CRM import lists |
| **crm_raw_records** | selltonai-modal | selltonai | Raw CSV data |

### Document & Email Tables

| Table | Primary Writer | Primary Readers | Purpose |
|-------|---------------|-----------------|---------|
| **organization_files** | selltonai-modal | selltonai | Uploaded documents |
| **organization_files_chunks** | selltonai-modal | selltonai | Document chunks |
| **email_accounts** | selltonai-gmail-api | selltonai, modal | Gmail OAuth tokens |
| **email_tokens** | selltonai-gmail-api | selltonai-modal | Email token tracking |

### ICP & Settings Tables

| Table | Primary Writer | Primary Readers | Purpose |
|-------|---------------|-----------------|---------|
| **organization_icp_linkedin_urls** | selltonai-modal | selltonai | ICP URL lists |
| **style_guidelines** | selltonai-modal | selltonai | Writing style guidelines |
| **deep_research_settings** | selltonai-modal | selltonai | Research provider settings |

---

## Schema Contracts

### organizations

```sql
CREATE TABLE organizations (
  id text PRIMARY KEY,  -- Clerk org ID
  name text NOT NULL,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
```

**Written by**: selltonai-onboard (create), backoffice (update)  
**Read by**: All services  
**Constraints**: `id` must match Clerk organization ID

---

### campaigns

```sql
CREATE TABLE campaigns (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES organizations(id),
  name text NOT NULL,
  status text DEFAULT 'draft' CHECK (status IN ('draft', 'active', 'paused', 'completed')),
  lead_source text CHECK (lead_source IN ('csv', 'template_csv', 'crm_list', 'manual', 'b2b_search', 'research')),
  total_companies integer DEFAULT 0,
  -- ... many more fields
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
```

**Written by**: selltonai-modal (CRUD)  
**Read by**: selltonai (display), backoffice (oversight)  
**Critical Fields**: `status`, `lead_source`, `total_companies` - must be kept current

---

### companies

```sql
CREATE TABLE companies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES organizations(id),
  name text NOT NULL,
  processing_status text DEFAULT 'scheduled' CHECK (processing_status IN ('scheduled', 'processing', 'processed', 'failed', 'blocked_by_icp', 'imported')),
  crm_list_id text,  -- From CRM import
  -- ... enrichment fields (JSONB)
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
```

**Written by**: selltonai-modal (CRUD), selltonai-crawler (enrichment updates)  
**Read by**: selltonai (display), backoffice (oversight)  
**Unique**: `(organization_id, name)` for upsert operations

---

### contacts

```sql
CREATE TABLE contacts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES organizations(id),
  email text,
  pipeline_stage text DEFAULT 'prospect',
  -- ... enrichment fields (JSONB)
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
```

**Written by**: selltonai-modal (CRUD)  
**Read by**: selltonai (display), backoffice (oversight)  
**Unique**: `(organization_id, email)` - one contact per email per org

---

### tasks

```sql
CREATE TABLE tasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES organizations(id),
  task_type text NOT NULL CHECK (task_type IN ('company_verification', 'email_copy', 'call_script', 'follow_up_email')),
  status text DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'completed', 'cancelled')),
  company_id uuid REFERENCES companies(id),
  contact_id uuid REFERENCES contacts(id),
  campaign_id uuid REFERENCES campaigns(id),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
```

**Written by**: selltonai-modal (CRUD)  
**Read by**: selltonai (task review), backoffice (oversight)  
**Critical**: Tasks created in Step 6 of company processing pipeline

---

## Row Level Security (RLS)

### Policy Pattern

All tables enforce RLS for frontend access:

```sql
-- Enable RLS
ALTER TABLE table_name ENABLE ROW LEVEL SECURITY;

-- Select policy
CREATE POLICY "Users can view data for their organization"
  ON table_name FOR SELECT
  USING (organization_id = current_setting('app.current_org_id', true));

-- Insert policy
CREATE POLICY "Users can insert data for their organization"
  ON table_name FOR INSERT
  WITH CHECK (organization_id = current_setting('app.current_org_id', true));

-- Update policy
CREATE POLICY "Users can update data for their organization"
  ON table_name FOR UPDATE
  USING (organization_id = current_setting('app.current_org_id', true));

-- Delete policy
CREATE POLICY "Users can delete data for their organization"
  ON table_name FOR DELETE
  USING (organization_id = current_setting('app.current_org_id', true));
```

**Important**: Service role key bypasses RLS. Anon key enforces RLS.

---

## Migration Conventions

### File Location

```
supabase/migrations/
├── release_1.0.0/        # Released migrations
├── release_1.0.2/
├── release_1.0.3/
├── release_1.0.4/
└── next-release/         # Unreleased migrations
    ├── 224_create_crm_tables.sql
    ├── 232_add_crm_list_id_column.sql
    └── ...
```

### Naming Convention

```
{number}_{description}.sql

Examples:
224_create_crm_tables.sql
232_add_crm_list_id_column.sql
233_add_imported_status.sql
234_add_both_record_type.sql
```

### Migration Template

```sql
-- Migration: Description
-- Date: YYYY-MM-DD
-- Description: What this migration does
-- Affected services: selltonai, selltonai-modal, etc.

-- SQL changes
ALTER TABLE table_name ADD COLUMN column_name type;

-- Add comment
COMMENT ON COLUMN table_name.column_name IS 'Description of column';

-- Add indexes
CREATE INDEX idx_table_name_column_name ON table_name(column_name);
```

---

## Index Strategy

### Performance Indexes

```sql
-- Organization-scoped queries
CREATE INDEX idx_table_name_org_id ON table_name(organization_id);

-- Status filtering
CREATE INDEX idx_table_name_status ON table_name(status);

-- Compound indexes for common queries
CREATE INDEX idx_table_name_org_status ON table_name(organization_id, status);

-- Partial indexes for specific conditions
CREATE INDEX idx_table_name_pending ON table_name(organization_id, status) 
  WHERE status = 'pending';
```

### Current Performance Indexes

| Table | Indexes | Purpose |
|-------|---------|---------|
| campaigns | org_id, status, created_at | Campaign listing |
| companies | org_id, processing_status, campaign_id | Company filtering |
| contacts | org_id, email, pipeline_stage | Contact search |
| tasks | org_id, status, campaign_id | Task management |
| crm_raw_records | list_id, org_id, import_status | CRM import queries |

---

## JSONB Field Contracts

### companies.b2b_result

```typescript
{
  id?: string;
  name?: string;
  website?: string;
  linkedin_url?: string;
  employee_count?: number;
  industries?: string[];
  description?: string;
  // ... other enrichment data
}
```

### companies.icp_score

```typescript
{
  score: number;           // 0-100
  grade: string;           // A, B, C, D, F
  reasons: string[];       // Why this score
  calculated_at: string;   // ISO timestamp
}
```

### contacts.location

```typescript
{
  city?: string;
  state?: string;
  country?: string;
  raw?: string;           // Original location string
}
```

---

## Shared Enums

```sql
-- Company processing status
CREATE TYPE company_processing_status AS ENUM (
  'scheduled', 'processing', 'processed', 'failed', 'blocked_by_icp', 'imported'
);

-- Contact pipeline stage
CREATE TYPE pipeline_stage AS ENUM (
  'prospect', 'appointment_requested', 'qualified', 'proposal', 
  'negotiation', 'won', 'lost', 'not_interested'
);

-- Task type
CREATE TYPE task_type AS ENUM (
  'company_verification', 'email_copy', 'call_script', 'follow_up_email'
);

-- Task status
CREATE TYPE task_status AS ENUM (
  'pending', 'approved', 'rejected', 'completed', 'cancelled'
);
```

**Important**: Enum changes require migration and coordination with all services.

---

## Data Lifecycle

### Campaign Data

```
Created (draft) → Started (active) → Processing (cron) → Completed
                                                    ↓
                                              Tasks created
                                                    ↓
                                            Emails sent
                                                    ↓
                                          Stats aggregated
```

### Company Data

```
Scheduled → Processing → Processed (success)
                    → Failed (error)
                    → Blocked (ICP filter)
                    → Imported (from CRM)
```

### CRM Import Data

```
CSV Upload → Raw records (unknown) → Processing → Extracted
                                                ↓
                                      Companies + Contacts created
                                                ↓
                                      Relationships linked
```

---

## Backup & Recovery

### Automated Backups

- Supabase handles daily backups
- Point-in-time recovery available
- Retention: 7 days (Pro plan)

### Manual Backups

```bash
# Export database
pg_dump -h db.xxx.supabase.co -U postgres sellton > backup.sql

# Import database
psql -h db.xxx.supabase.co -U postgres sellton < backup.sql
```

---

## Environment Variables

```env
# All services use these
SUPABASE_URL=https://xxx.supabase.co
SUPABASE_ANON_KEY=eyJxxx         # Frontend (RLS enforced)
SUPABASE_SERVICE_ROLE_KEY=eyJxxx  # Backend (RLS bypassed)
```

---

## Testing

### Local Development

```bash
# Start local Supabase
supabase start

# Apply migrations
supabase db reset

# Generate types
supabase gen types typescript --local > src/types/database.ts
```

### Migration Testing

```bash
# Test migration locally
supabase migration up

# Rollback if needed
supabase migration down
```

---

**Last Updated**: April 6, 2026  
**Maintained By**: Database team, update on schema changes  
**Purpose**: Shared database contracts for all services
