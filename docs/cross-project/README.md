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
| **organization** | selltonai-onboard | All | Organization accounts |
| **user** | selltonai-onboard | All | Canonical user identities and email addresses |
| **user_organizations** | selltonai-onboard | All | User-org membership |
| **internal_support_users** | backoffice | selltonai-modal | Internal staff identities excluded from customer billing |
| **support_workspace_sessions** | backoffice | selltonai, backoffice | Short-lived non-member support access sessions |
| **support_audit_events** | selltonai, backoffice | backoffice | Audit log for support access and actions |
| **support_resource_locks** | selltonai, backoffice | selltonai, backoffice | Optional edit locks for risky support writes |
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
| **ai_ark_enrollment_runs** | selltonai-modal | backoffice | Idempotency ledger for AI-Ark enrollment recovery |

### CRM Tables

| Table | Primary Writer | Primary Readers | Purpose |
|-------|---------------|-----------------|---------|
| **crm_lists** | selltonai-modal | selltonai | CRM import lists |
| **crm_list_members** | selltonai-modal | selltonai | Manual memberships for existing contacts/companies in CRM lists |
| **crm_raw_records** | selltonai-modal | selltonai | Raw CSV data |
| **crm_import_jobs** | selltonai-modal | selltonai via Modal API | Durable progress for large CRM CSV imports |

### Document & Email Tables

| Table | Primary Writer | Primary Readers | Purpose |
|-------|---------------|-----------------|---------|
| **organization_files** | selltonai-modal | selltonai | Uploaded documents |
| **organization_files_chunks** | selltonai-modal | selltonai | Document chunks |
| **email_accounts** | selltonai-gmail-api | selltonai, modal | Gmail OAuth tokens |
| **email_tokens** | selltonai-gmail-api | selltonai-modal | Email token tracking |
| **unmatched_replies** | selltonai-modal | backoffice | Incoming replies that could not be mapped to a contact |

`organization_files.file_category` values currently include `documents`, `transcripts`, `linkedin_voice`, `internal_documents`, `sales_papers`, `sait_guidelines`, `brand_guidelines`, `case_study`, and `sales_scripts`. New values must be added to the Supabase enum and kept aligned in `selltonai`, `selltonai-modal`, and `selltonai-vector-api`.

### Billing Tables

| Table | Primary Writer | Primary Readers | Purpose |
|-------|---------------|-----------------|---------|
| **billing_customers** | selltonai-modal | selltonai, backoffice | Workspace billing settings, monthly spend limits, and optional Stripe customer/payment details |
| **billing_invoices** | selltonai-modal | selltonai, backoffice | Usage invoices, totals, Stripe invoice ids, and hosted invoice links |
| **billing_invoice_sequences** | selltonai-modal | selltonai-modal | Year-scoped reservation state for explicit Stripe invoice numbers like `SLTN-2026/100001` |
| **usage** | selltonai-modal | selltonai, backoffice | Billable usage rows linked to generated invoices |

`billing_customers.auto_charge_enabled=false` marks a workspace as non-billable in Stripe. `selltonai-modal` must skip scheduled invoices, bill-now, and manual invoice payment while the flag is false. Usage rows remain unstamped/uninvoiced so monthly spend-limit enforcement can still block work when the configured limit is reached.

Billing work-access overrides live on the singular `organization` table because some workspaces do not have `billing_customers` rows yet. Backoffice writes the override fields, while `selltonai-modal` and `selltonai` enforce the effective decision.

```sql
work_access_mode text not null default 'auto'
work_access_reason text
work_access_until timestamptz
work_access_updated_by text
work_access_updated_at timestamptz
```

Allowed `work_access_mode` values:

- `auto`: follow billing and spend-limit automation.
- `force_allow`: allow billable/outbound work even when billing is suspended.
- `force_block`: block billable/outbound work even when billing is healthy.

The legacy dispatch mirror remains on `organization`:

```sql
dispatch_suspended boolean
dispatch_suspended_reason text
dispatch_suspended_at timestamptz
```

During staggered environment upgrades, readers must tolerate missing `work_access_*` columns and fall back to the legacy dispatch fields.

Backoffice reads `backoffice_billing_workspace_rollup_v1(p_start, p_end)` for the `/billing`
workspace list when available. The function is additive and returns one row per workspace with
usage, uninvoiced usage, invoices, billing customer state, and organization work-access fields for a
selected period.

### ICP & Settings Tables

| Table | Primary Writer | Primary Readers | Purpose |
|-------|---------------|-----------------|---------|
| **organization_icp_linkedin_urls** | selltonai-modal | selltonai | ICP URL lists |
| **style_guidelines** | selltonai-modal | selltonai | Writing style guidelines |
| **deep_research_settings** | selltonai-modal | selltonai | Research provider settings |
| **prompts** | backoffice, selltonai-modal sync script | selltonai-modal, backoffice | Global master Jinja prompt templates |
| **org_prompt_overrides** | backoffice | selltonai-modal, backoffice | Optional per-workspace prompt override content |
| **prompt_revisions** | backoffice | backoffice | Prompt edit snapshots for audit and rollback |

Prompt resolution in `selltonai-modal` is override → master → checked-in file fallback.
Master prompts are workspace-independent; workspace-specific modifications live only in
`org_prompt_overrides`.

### Onboarding Tables

| Table | Primary Writer | Primary Readers | Purpose |
|-------|---------------|-----------------|---------|
| **onboarding_research** | selltonai-modal | selltonai | V1/V2 onboarding research state |
| **onboarding_funnel_events** | selltonai, selltonai-modal | selltonai, backoffice | Funnel transition audit log |
| **onboarding_reengagement_sends** | backoffice | backoffice | Idempotent onboarding lifecycle email send ledger |
| **email_sequence_steps** | backoffice | backoffice | Configurable onboarding lifecycle email drip steps |
| **email_suppressions** | backoffice | backoffice | Manual suppressions for lifecycle/broadcast sends |
| **email_broadcasts** | backoffice | backoffice | Reserved operator broadcast definitions |
| **email_broadcast_sends** | backoffice | backoffice | Reserved broadcast send ledger |
| **avatar_interviews** | selltonai | selltonai-modal, selltonai | Retell call tracking for onboarding and sender voice |
| **sender_voice** | selltonai-modal | selltonai | Per-user LinkedIn writing voice distilled from Retell |

Backoffice drains active `email_sequence_steps` via `emails:tick`.
Migration `344_email-sequence-audience-mode.sql` adds `audience_mode` with
`not_activated` as the default for existing and new rows. In this mode Backoffice
targets every workspace old enough for the step while `activation_paid_at` is
null and no `billing_customers.card_brand/card_last4` exists. The optional
`funnel_stage` mode preserves `find_funnel_dropouts()` targeting. Both modes use
`onboarding_reengagement_sends` for per-workspace/step idempotency and honor
`email_suppressions` before delivery.

---

## Schema Contracts

The canonical core tables use the singular names `organization` and `user`. The membership join
table remains plural as `user_organizations`. Consumers must not substitute plural
`organizations` or `users` endpoints: those relations do not exist in production.

### organization

```sql
CREATE TABLE organization (
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
  organization_id text NOT NULL REFERENCES organization(id),
  name text NOT NULL,
  status campaign_status DEFAULT 'draft',
  lead_source text CHECK (lead_source IN ('csv', 'template_csv', 'crm_list', 'manual', 'b2b_search', 'research')),
  allow_competitor_outreach boolean DEFAULT false,
  total_companies integer DEFAULT 0,
  -- ... many more fields
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
```

**Written by**: selltonai-modal (CRUD)  
**Read by**: selltonai (display), backoffice (oversight)  
**Critical Fields**: `status`, `lead_source`, `total_companies`, `allow_competitor_outreach` - must be kept current

Competitor exclusion is always active. `allow_competitor_outreach` remains as a deprecated compatibility column and must stay `false`; `selltonai-modal` marks detected competitor companies and skips task/email drafting.

**Status Values**: `draft`, `active`, `paused`, `discovery_completed`, `completed` (legacy final), `fully_completed`, `cancelled`

---

### companies

```sql
CREATE TABLE companies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES organizations(id),
  name text NOT NULL,
  processing_status text DEFAULT 'scheduled' CHECK (processing_status IN ('scheduled', 'processing', 'processed', 'failed', 'blocked_by_icp', 'imported')),
  is_competitor boolean DEFAULT false,
  competitor_detection_source text,
  competitor_detection_reason text,
  competitor_detection_confidence numeric(4,3),
  crm_list_id text,  -- From CRM import
  -- ... enrichment fields (JSONB)
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
```

**Written by**: selltonai-modal (CRUD), selltonai-crawler (enrichment updates)  
**Read by**: selltonai (display), backoffice (oversight)  
**Unique**: `(organization_id, name)` for upsert operations

Competitor classification lives on `companies`. `is_competitor=true` is global to the organization, and campaigns must always skip those companies for outreach.

---

### contacts

```sql
CREATE TABLE contacts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES organizations(id),
  email text,
  pipeline_stage text DEFAULT 'prospect',
  processing_status text DEFAULT 'pending',
  last_reply_sentiment text,
  last_reply_sub_intent text,
  last_reply_at timestamptz,
  -- ... enrichment fields (JSONB)
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
```

**Written by**: selltonai-modal (CRUD)
**Read by**: selltonai (display), backoffice (oversight)
**Unique**: `(organization_id, email)` - one contact per email per org
**Cleanup status**: `phantom_pending_rediscovery` marks legacy placeholder contacts. These rows are preserved, but selltonai-modal treats them as non-real contacts for AI-Ark enrollment recovery.

---

### ai_ark_enrollment_runs

```sql
CREATE TABLE ai_ark_enrollment_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  enrollment_id text NOT NULL,
  campaign_id uuid NOT NULL REFERENCES campaigns(id),
  company_id uuid NOT NULL REFERENCES companies(id),
  organization_id text NOT NULL REFERENCES organizations(id),
  status text NOT NULL DEFAULT 'running',
  result_count integer NOT NULL DEFAULT 0,
  error_message text,
  run_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
```

**Written by**: selltonai-modal campaign start recovery
**Read by**: backoffice/support
**Unique**: `(enrollment_id, company_id)` prevents duplicate AI-Ark searches for the same campaign/company

---

### unmatched_replies

```sql
CREATE TABLE unmatched_replies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES organizations(id),
  email_id text,
  thread_id text,
  account_id text,
  from_email text,
  to_emails text[] DEFAULT '{}',
  raw_payload jsonb DEFAULT '{}',
  classification_snapshot jsonb DEFAULT '{}',
  resolution_status text DEFAULT 'unmatched',
  resolved_contact_id uuid REFERENCES contacts(id),
  resolved_company_id uuid REFERENCES companies(id),
  resolved_campaign_id uuid REFERENCES campaigns(id),
  received_at timestamptz DEFAULT now()
);
```

**Written by**: selltonai-modal incoming email webhook
**Read by**: backoffice/support
**Unique**: `email_id` when present, so webhook retries do not duplicate persisted orphan replies

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
├── release_1.1.1/
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

Large CSV imports also write progress into `crm_import_jobs`:

```
queued → importing/raw_import → processing/classification
                                → processing/companies
                                → processing/contacts
                                → processing/relationships
                                → completed
                                → failed
```

`selltonai-modal` is the writer for `crm_import_jobs` and exposes progress to `selltonai` through `GET /lists/{list_id}/import-status`.

---

## Backup & Recovery

### Hetzner migration runner

Self-hosted stage and production PostgreSQL migrations use the explicit operator runner in
`operations/hetzner-migrations/`. Operators pass the exact ordered SQL paths from the checked-out
branch; the runner never scans by numeric prefix because migration numbers collide between branches.

```bash
./operations/hetzner-migrations/migrate.sh status stage
./operations/hetzner-migrations/migrate.sh plan stage migrations/release_1.3.0/344_email-sequence-audience-mode.sql
./operations/hetzner-migrations/migrate.sh apply stage migrations/release_1.3.0/344_email-sequence-audience-mode.sql
```

Migration identity is full repository path plus SHA-256. Applies use `supabase_admin`, take and
validate a full backup, lock per environment, transact each migration together with its private
ledger entry, and notify PostgREST after success. Production additionally requires
`--confirm-production` and refuses schema changes during active logical-replication/standby windows.
See `operations/hetzner-migrations/README.md` for the production command and safety contract.

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

**Last Updated**: May 20, 2026
**Maintained By**: Database team, update on schema changes  
**Purpose**: Shared database contracts for all services
