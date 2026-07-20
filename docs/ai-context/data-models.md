# Data Models - Supabase

## Overview

This document provides comprehensive documentation of the Sellton database schema managed by the supabase project. It serves as the **source of truth** for all database tables, columns, relationships, indexes, and constraints across all Sellton services.

The database uses **PostgreSQL 15** with **Supabase** enhancements, including:
- Row Level Security (RLS) on all public tables
- Real-time subscriptions
- JSONB for flexible data storage
- Custom enum types
- Comprehensive indexing

---

## Table of Contents

1. [Core Tables](#core-tables)
2. [Campaign & Company Tables](#campaign--company-tables)
3. [Contact & Task Tables](#contact--task-tables)
4. [CRM Tables](#crm-tables)
5. [Document & Email Tables](#document--email-tables)
6. [Billing Tables](#billing-tables)
7. [AI & Research Tables](#ai--research-tables)
8. [LinkedIn Integration Tables](#linkedin-integration-tables)
9. [Enum Types](#enum-types)
10. [RLS Policies](#rls-policies)
11. [Indexes](#indexes)
12. [JSONB Schemas](#jsonb-schemas)
13. [Data Lifecycle](#data-lifecycle)

---

## Core Tables

The canonical core tables use the singular names `organization` and `user`. The membership join
table remains plural as `user_organizations`. Production does not expose plural `organizations`
or `users` relations.

### organization

**Primary Writer**: sellton-onboard (via Clerk webhook), backoffice  
**Primary Readers**: All services  
**Purpose**: Top-level tenant isolation

| Column | Type | Constraints | Description | RLS |
|--------|------|-------------|-------------|-----|
| `id` | text | PK | Organization ID (Clerk org ID) | ✅ |
| `name` | text | NOT NULL | Organization name | ✅ |
| `onboarding_status` | text | | Current onboarding phase | ✅ |
| `work_access_mode` | text | DEFAULT 'auto' | Billing access mode | ✅ |
| `work_access_reason` | text | | Reason for access override | ✅ |
| `work_access_until` | timestamptz | | Access override expiration | ✅ |
| `work_access_updated_by` | text | | Who set the access override | ✅ |
| `work_access_updated_at` | timestamptz | | When access was updated | ✅ |
| `dispatch_suspended` | boolean | | Legacy dispatch suspension flag | ✅ |
| `dispatch_suspended_reason` | text | | Reason for suspension | ✅ |
| `dispatch_suspended_at` | timestamptz | | When suspended | ✅ |
| `created_at` | timestamptz | DEFAULT now() | Creation timestamp | ✅ |
| `updated_at` | timestamptz | DEFAULT now() | Last update timestamp | ✅ |

**Indexes**:
- PK: `organization_pkey` ON `id`

**Relationships**:
- 1:N → `campaigns`
- 1:N → `companies`
- 1:N → `contacts`
- 1:N → `user` (via `user_organizations`)
- 1:N → `organization_settings`
- 1:N → `organization_files`

**RLS Policies**:
- SELECT: `organization_id = current_setting('app.current_org_id', true)`
- INSERT: `organization_id = current_setting('app.current_org_id', true)`
- UPDATE: `organization_id = current_setting('app.current_org_id', true)`
- DELETE: `organization_id = current_setting('app.current_org_id', true)`

---

### user

**Primary Writer**: sellton-onboard (via Clerk webhook)  
**Primary Readers**: All services  
**Purpose**: User account information

| Column | Type | Constraints | Description | RLS |
|--------|------|-------------|-------------|-----|
| `id` | text | PK | User ID (Clerk user ID) | ✅ |
| `email` | text | | User email address | ✅ |
| `created_at` | timestamptz | DEFAULT now() | Creation timestamp | ✅ |

Names, avatars, and other profile presentation fields belong to `user_profiles`; they are not
columns on the canonical `user` identity table.

**Indexes**:
- PK: `user_pkey` ON `id`

**RLS Policies**:
- SELECT: Users can view their own profile or profiles in their organizations
- UPDATE: Users can update their own profile

---

### user_organizations

**Primary Writer**: sellton-onboard (via Clerk webhook)  
**Primary Readers**: All services  
**Purpose**: User-org membership mapping

| Column | Type | Constraints | Description | RLS |
|--------|------|-------------|-------------|-----|
| `user_id` | text | PK, FK → user(id) | User reference | ✅ |
| `organization_id` | text | PK, FK → organization(id) | Organization reference | ✅ |
| `role` | text | NOT NULL | User role in organization | ✅ |
| `created_at` | timestamptz | DEFAULT now() | Creation timestamp | ✅ |

**Roles**:
- `admin` - Full access to organization
- `member` - Standard access

**Indexes**:
- PK: `user_organizations_pkey` ON `(user_id, organization_id)`
- FK: `user_organizations_user_id_fkey` ON `user_id`
- FK: `user_organizations_organization_id_fkey` ON `organization_id`

---

### organization_settings

**Primary Writer**: backoffice, selltonai  
**Primary Readers**: All services  
**Purpose**: Per-organization configuration

| Column | Type | Constraints | Description | RLS |
|--------|------|-------------|-------------|-----|
| `id` | uuid | PK DEFAULT gen_random_uuid() | Settings ID | ✅ |
| `organization_id` | text | NOT NULL, FK → organizations(id) | Owning organization | ✅ |
| `settings` | jsonb | DEFAULT '{}' | Configuration settings | ✅ |
| `created_at` | timestamptz | DEFAULT now() | Creation timestamp | ✅ |
| `updated_at` | timestamptz | DEFAULT now() | Last update timestamp | ✅ |

**Indexes**:
- `idx_organization_settings_org_id` ON `organization_id`
- UNIQUE: `organization_settings_org_id_key` ON `organization_id`

---

## Campaign & Company Tables

### campaigns

**Primary Writer**: selltonai-modal  
**Primary Readers**: selltonai, backoffice  
**Purpose**: Sales campaign management

| Column | Type | Constraints | Description | RLS |
|--------|------|-------------|-------------|-----|
| `id` | uuid | PK DEFAULT gen_random_uuid() | Campaign ID | ✅ |
| `organization_id` | text | NOT NULL, FK → organizations(id) | Owning organization | ✅ |
| `name` | text | NOT NULL | Campaign name | ✅ |
| `description` | text | | Campaign description | ✅ |
| `status` | text | DEFAULT 'draft' | Campaign status | ✅ |
| `campaign_type` | text | DEFAULT 'email' | Campaign type | ✅ |
| `lead_source` | text | | csv, template_csv, crm_list, manual, b2b_search, research | ✅ |
| `total_companies` | integer | DEFAULT 0 | Number of companies in campaign | ✅ |
| `estimated_total_companies` | integer | | Estimated total from lookalikes | ✅ |
| `processed_companies` | integer | DEFAULT 0 | Companies processed so far | ✅ |
| `wizard_completed` | boolean | DEFAULT false | Campaign wizard completed | ✅ |
| `auto_reload_enabled` | boolean | DEFAULT true | Cron job auto-processing enabled | ✅ |
| `company_fetch_limit` | integer | | Max companies to fetch total | ✅ |
| `daily_company_fetch_limit` | integer | | Max companies per day | ✅ |
| `daily_fetch_count` | integer | DEFAULT 0 | Daily fetch counter | ✅ |
| `daily_fetch_date` | date | | Date of daily counter | ✅ |
| `product_description` | text | | Product/service description | ✅ |
| `language` | text | DEFAULT 'en' | Campaign language | ✅ |
| `campaign_timezone` | text | | Campaign timezone | ✅ |
| `icp_min_employees` | integer | | ICP minimum employees filter | ✅ |
| `icp_max_employees` | integer | | ICP maximum employees filter | ✅ |
| `icp_industries` | text[] | | ICP industry codes | ✅ |
| `icp_job_titles` | text[] | | ICP job titles | ✅ |
| `icp_keywords` | text[] | | ICP keywords | ✅ |
| `icp_pain_points` | text[] | | ICP pain points | ✅ |
| `icp_focus_areas` | text[] | | ICP focus areas | ✅ |
| `icp_primary_regions` | text[] | | ICP primary regions | ✅ |
| `icp_secondary_regions` | text[] | | ICP secondary regions | ✅ |
| `icp_locations` | text[] | | ICP location strings | ✅ |
| `icp_profile_id` | text | | Reference to ICP profile | ✅ |
| `selected_company_ids` | uuid[] | | Selected company IDs for CRM list campaigns | ✅ |
| `csv_results` | jsonb | | CSV upload results and metadata | ✅ |
| `csv_template_upload` | boolean | DEFAULT false | Template CSV upload mode | ✅ |
| `b2b_results` | jsonb | | B2B search results for manual campaigns | ✅ |
| `curated_companies` | jsonb | | Curated company data with selection status | ✅ |
| `deep_research_provider` | text | | Deep research provider (none, exa, perplexity, gemini) | ✅ |
| `deep_research_types` | text[] | | Research types enabled | ✅ |
| `phone_discovery_mode` | text | | Phone discovery mode | ✅ |
| `metadata` | jsonb | | Additional campaign metadata | ✅ |
| `goal_source` | text | | Source of campaign goal (onboarding_auto, etc.) | ✅ |
| `goal` | text | | Campaign goal | ✅ |
| `b2b_search_filters` | jsonb | | B2B search filters | ✅ |
| `started_at` | timestamptz | | Campaign start timestamp | ✅ |
| `created_at` | timestamptz | DEFAULT now() | Creation timestamp | ✅ |
| `updated_at` | timestamptz | DEFAULT now() | Last update timestamp | ✅ |

**Status Values**: `draft`, `active`, `paused`, `discovery_completed`, `completed` (legacy final), `fully_completed`, `cancelled`

`discovery_completed` means AI-Ark/lookalike discovery and company processing are exhausted while outreach follow-ups may still run. `fully_completed` is the final state after follow-up sequences and open campaign tasks are drained.

**Lead Source Values**: `csv`, `template_csv`, `crm_list`, `manual`, `b2b_search`, `research`

**Indexes**:
- `idx_campaigns_org_id` ON `campaigns(organization_id)`
- `idx_campaigns_status` ON `campaigns(status)`
- `idx_campaigns_created_at` ON `campaigns(created_at)`
- `idx_campaigns_org_status` ON `campaigns(organization_id, status)`

---

### companies

**Primary Writer**: selltonai-modal, selltonai-crawler  
**Primary Readers**: selltonai, backoffice  
**Purpose**: Company records with enrichment data

| Column | Type | Constraints | Description | RLS |
|--------|------|-------------|-------------|-----|
| `id` | uuid | PK DEFAULT gen_random_uuid() | Company ID | ✅ |
| `organization_id` | text | NOT NULL, FK → organizations(id) | Owning organization | ✅ |
| `name` | text | NOT NULL | Company name | ✅ |
| `website` | text | | Company website URL | ✅ |
| `linkedin_url` | text | | LinkedIn company URL | ✅ |
| `description` | text | | Company description | ✅ |
| `phone` | text | | Company phone number | ✅ |
| `logo` | text | | Logo URL | ✅ |
| `size` | text | | Company size range (e.g., "50-100") | ✅ |
| `location` | text | | Company location/headquarters | ✅ |
| `employee_count` | integer | | Number of employees | ✅ |
| `founded_year` | integer | | Year company was founded | ✅ |
| `followers` | integer | | LinkedIn followers | ✅ |
| `industries` | text[] | | Industry codes/names | ✅ |
| `specialities` | text[] | | Company specialities | ✅ |
| `hashtags` | text[] | | Company hashtags | ✅ |
| `processing_status` | company_processing_status | DEFAULT 'scheduled' | Company processing state | ✅ |
| `contact_extraction_status` | enum | | pending, processing, processed, failed | ✅ |
| `icp_score` | jsonb | | ICP scoring result | ✅ |
| `deep_research` | jsonb | | Deep research v1 result | ✅ |
| `deep_research_v2` | jsonb | | Deep research v2 result | ✅ |
| `outreach_strategy` | jsonb | | AI-generated outreach strategy | ✅ |
| `b2b_enrichment` | jsonb | | B2B enrichment data | ✅ |
| `b2b_result` | jsonb | | B2B API result (raw) | ✅ |
| `useful_case_file_ids` | uuid[] | | Related document file IDs | ✅ |
| `crm_list_id` | text | | CRM list ID this company was imported from | ✅ |
| `campaign_id` | uuid | FK → campaigns(id) | Campaign this company belongs to | ✅ |
| `linkedin_account_id` | uuid | | LinkedIn account reference | ✅ |
| `channel_strategy` | jsonb | | Channel strategy configuration | ✅ |
| `created_at` | timestamptz | DEFAULT now() | Creation timestamp | ✅ |
| `updated_at` | timestamptz | DEFAULT now() | Last update timestamp | ✅ |

**Processing Status Values**: `scheduled`, `processing`, `processed`, `failed`, `blocked_by_icp`, `imported`

**Indexes**:
- `idx_companies_org_id` ON `companies(organization_id)`
- `idx_companies_processing_status` ON `companies(processing_status)`
- `idx_companies_campaign_id` ON `companies(campaign_id)`
- `idx_companies_crm_list_id` ON `companies(crm_list_id)` WHERE `crm_list_id IS NOT NULL`
- `idx_companies_org_status` ON `companies(organization_id, processing_status)`
- `idx_companies_icp_score_gin` ON `companies` USING GIN (`icp_score`)

---

### contacts

**Primary Writer**: selltonai-modal  
**Primary Readers**: selltonai, backoffice  
**Purpose**: Contact/person records with pipeline stage and enrichment

| Column | Type | Constraints | Description | RLS |
|--------|------|-------------|-------------|-----|
| `id` | uuid | PK DEFAULT gen_random_uuid() | Contact ID | ✅ |
| `organization_id` | text | NOT NULL, FK → organizations(id) | Owning organization | ✅ |
| `name` | text | NOT NULL | Full name | ✅ |
| `firstname` | text | | First name | ✅ |
| `lastname` | text | | Last name | ✅ |
| `email` | text | | Email address (unique per org) | ✅ |
| `linkedin_url` | text | | LinkedIn profile URL | ✅ |
| `headline` | text | | LinkedIn headline/title | ✅ |
| `summary` | text | | LinkedIn summary | ✅ |
| `phone` | text | | Phone number | ✅ |
| `location` | jsonb | | Location data | ✅ |
| `open_to_work` | boolean | DEFAULT false | Open to work flag | ✅ |
| `influencer` | boolean | DEFAULT false | Influencer flag | ✅ |
| `premium` | boolean | DEFAULT false | Premium account flag | ✅ |
| `b2b_email_requested` | boolean | DEFAULT false | B2B email API requested | ✅ |
| `email_search_status` | email_search_status | | finished_searching_email, search_not_started, searching | ✅ |
| `pipeline_stage` | pipeline_stage | DEFAULT 'prospect' | Contact pipeline stage | ✅ |
| `ooo_until` | timestamptz | | Out-of-office until date | ✅ |
| `unsubscribed_at` | timestamptz | | Unsubscribe timestamp | ✅ |
| `stop_drafts` | boolean | DEFAULT false | Stop generating draft emails | ✅ |
| `last_email_sentiment` | text | | Last email sentiment analysis | ✅ |
| `last_email_intent` | text | | Last email intent classification | ✅ |
| `last_thread_id` | text | | Last Gmail thread ID | ✅ |
| `last_incoming_email_at` | timestamptz | | Last incoming email timestamp | ✅ |
| `last_reply_sentiment` | text | | Last reply sentiment | ✅ |
| `last_reply_sub_intent` | text | | Last reply sub-intent | ✅ |
| `last_reply_at` | timestamptz | | Last reply timestamp | ✅ |
| `educations` | jsonb | | Education history | ✅ |
| `certifications` | jsonb | | Certifications | ✅ |
| `languages` | jsonb | | Languages spoken | ✅ |
| `skills` | jsonb | | Skills list | ✅ |
| `analysis` | jsonb | | AI analysis of profile | ✅ |
| `processing_status` | text | DEFAULT 'pending' | Contact processing status | ✅ |
| `crm_list_id` | text | | CRM list ID if from import | ✅ |
| `linkedin_profile` | jsonb | | LinkedIn profile data | ✅ |
| `created_at` | timestamptz | DEFAULT now() | Creation timestamp | ✅ |
| `updated_at` | timestamptz | DEFAULT now() | Last update timestamp | ✅ |

**Pipeline Stage Values**: `prospect`, `appointment_requested`, `qualified`, `proposal`, `negotiation`, `won`, `lost`, `not_interested`

**Processing Status Values**: `pending`, `processing`, `completed`, `processed`, `failed`, `imported`, `phantom`, `phantom_pending_rediscovery`

**Indexes**:
- `idx_contacts_org_id` ON `contacts(organization_id)`
- `idx_contacts_email` ON `contacts(email)`
- `idx_contacts_pipeline_stage` ON `contacts(pipeline_stage)`
- `idx_contacts_org_email` ON `contacts(organization_id, email)`

---

### company_contacts

**Primary Writer**: selltonai-modal  
**Primary Readers**: selltonai  
**Purpose**: Junction table linking companies to contacts

| Column | Type | Constraints | Description | RLS |
|--------|------|-------------|-------------|-----|
| `id` | uuid | PK DEFAULT gen_random_uuid() | Relationship ID | ✅ |
| `company_id` | uuid | NOT NULL, FK → companies(id) | Company ID | ✅ |
| `contact_id` | uuid | NOT NULL, FK → contacts(id) | Contact ID | ✅ |
| `organization_id` | text | NOT NULL, FK → organizations(id) | Owning organization | ✅ |
| `created_at` | timestamptz | DEFAULT now() | Creation timestamp | ✅ |
| `updated_at` | timestamptz | DEFAULT now() | Last update timestamp | ✅ |

**Indexes**:
- `idx_company_contacts_company` ON `company_contacts(company_id)`
- `idx_company_contacts_contact` ON `company_contacts(contact_id)`
- `idx_company_contacts_org` ON `company_contacts(organization_id)`
- `idx_company_contacts_unique` ON `company_contacts(company_id, contact_id)` UNIQUE

---

## Contact & Task Tables

### tasks

**Primary Writer**: selltonai-modal  
**Primary Readers**: selltonai, backoffice  
**Purpose**: Verification and action tasks for user review

| Column | Type | Constraints | Description | RLS |
|--------|------|-------------|-------------|-----|
| `id` | uuid | PK DEFAULT gen_random_uuid() | Task ID | ✅ |
| `organization_id` | text | NOT NULL, FK → organizations(id) | Owning organization | ✅ |
| `task_type` | task_type | NOT NULL | Task type | ✅ |
| `status` | task_status | DEFAULT 'pending' | Task status | ✅ |
| `priority` | text | DEFAULT 'normal' | Task priority | ✅ |
| `company_id` | uuid | FK → companies(id) | Related company | ✅ |
| `contact_id` | uuid | FK → contacts(id) | Related contact | ✅ |
| `campaign_id` | uuid | FK → campaigns(id) | Related campaign | ✅ |
| `assigned_to` | text | FK → users(id) | Assigned user ID | ✅ |
| `title` | text | NOT NULL | Task title | ✅ |
| `description` | text | | Task description | ✅ |
| `metadata` | jsonb | | Additional task data | ✅ |
| `due_date` | timestamptz | | Task due date | ✅ |
| `completed_at` | timestamptz | | Task completion timestamp | ✅ |
| `created_at` | timestamptz | DEFAULT now() | Creation timestamp | ✅ |
| `updated_at` | timestamptz | DEFAULT now() | Last update timestamp | ✅ |

**Task Type Values**: `company_verification`, `email_copy`, `call_script`, `follow_up_email`

**Task Status Values**: `pending`, `approved`, `rejected`, `completed`, `cancelled`

**Priority Values**: `low`, `normal`, `high`, `urgent`

**Indexes**:
- `idx_tasks_campaign_id` ON `tasks(campaign_id)` WHERE `campaign_id IS NOT NULL`
- `idx_tasks_company_id` ON `tasks(company_id)` WHERE `company_id IS NOT NULL`
- `idx_tasks_contact_id` ON `tasks(contact_id)` WHERE `contact_id IS NOT NULL`
- `idx_tasks_org_status` ON `tasks(organization_id, status)`
- `idx_tasks_verification_no_campaign` ON `tasks(organization_id, task_type, status, company_id)` WHERE `task_type = 'company_verification' AND status = 'pending' AND campaign_id IS NULL`

---

## CRM Tables

### crm_lists

**Primary Writer**: selltonai-modal  
**Primary Readers**: selltonai  
**Purpose**: CRM import lists for organizing imported data

| Column | Type | Constraints | Description | RLS |
|--------|------|-------------|-------------|-----|
| `id` | uuid | PK DEFAULT gen_random_uuid() | List ID | ✅ |
| `organization_id` | text | NOT NULL, FK → organizations(id) | Owning organization | ✅ |
| `name` | text | NOT NULL | List name | ✅ |
| `description` | text | | List description | ✅ |
| `source` | text | NOT NULL | csv_import, manual, campaign_output | ✅ |
| `row_count` | integer | DEFAULT 0 | Number of records in list | ✅ |
| `created_at` | timestamptz | DEFAULT now() | Creation timestamp | ✅ |
| `updated_at` | timestamptz | DEFAULT now() | Last update timestamp | ✅ |

**Source Values**: `csv_import`, `manual`, `campaign_output`

---

### crm_raw_records

**Primary Writer**: selltonai-modal  
**Primary Readers**: selltonai-modal  
**Purpose**: Raw imported CSV data before extraction and processing

| Column | Type | Constraints | Description | RLS |
|--------|------|-------------|-------------|-----|
| `id` | uuid | PK DEFAULT gen_random_uuid() | Record ID | ✅ |
| `list_id` | uuid | FK → crm_lists(id) | CRM list ID | ✅ |
| `organization_id` | text | FK → organizations(id) | Owning organization | ✅ |
| `raw_data` | jsonb | DEFAULT '{}' | Original CSV row as JSON | ✅ |
| `record_type` | text | DEFAULT 'unknown' | company, person, unknown | ✅ |
| `extracted_company_id` | uuid | FK → companies(id) | Extracted company reference | ✅ |
| `extracted_person_id` | uuid | FK → contacts(id) | Extracted contact reference | ✅ |
| `import_status` | text | DEFAULT 'raw' | raw, extracted, failed | ✅ |
| `import_error` | text | | Error message if failed | ✅ |
| `created_at` | timestamptz | DEFAULT now() | Creation timestamp | ✅ |

**Record Type Values**: `unknown`, `company`, `person`

**Import Status Values**: `raw`, `extracted`, `failed`

**Indexes**:
- `idx_crm_raw_records_list_id` ON `crm_raw_records(list_id)`
- `idx_crm_raw_records_org_id` ON `crm_raw_records(organization_id)`
- `idx_crm_raw_records_import_status` ON `crm_raw_records(import_status)`
- `idx_crm_raw_records_record_type` ON `crm_raw_records(record_type)`
- `idx_crm_raw_records_extracted_company_id` ON `crm_raw_records(extracted_company_id)` WHERE `extracted_company_id IS NOT NULL`
- `idx_crm_raw_records_extracted_person_id` ON `crm_raw_records(extracted_person_id)` WHERE `extracted_person_id IS NOT NULL`

---

### crm_import_jobs

**Primary Writer**: selltonai-modal  
**Primary Readers**: selltonai-modal, selltonai (via API)  
**Purpose**: Durable progress for large CRM CSV imports

| Column | Type | Constraints | Description | RLS |
|--------|------|-------------|-------------|-----|
| `id` | uuid | PK DEFAULT gen_random_uuid() | Job ID | ✅ |
| `organization_id` | text | NOT NULL, FK → organizations(id) | Owning organization | ✅ |
| `list_id` | uuid | NOT NULL, FK → crm_lists(id) | CRM list ID | ✅ |
| `user_id` | text | | User who initiated import | ✅ |
| `status` | text | NOT NULL | queued, importing, processing, completed, failed | ✅ |
| `total_rows` | integer | | Total rows to import | ✅ |
| `imported_count` | integer | DEFAULT 0 | Rows imported | ✅ |
| `failed_count` | integer | DEFAULT 0 | Rows failed | ✅ |
| `current_phase` | text | | classification, companies, contacts, relationships | ✅ |
| `current_step` | integer | DEFAULT 0 | Current step in phase | ✅ |
| `error_message` | text | | Error if job failed | ✅ |
| `metadata` | jsonb | | Job metadata | ✅ |
| `created_at` | timestamptz | DEFAULT now() | Creation timestamp | ✅ |
| `updated_at` | timestamptz | DEFAULT now() | Last update timestamp | ✅ |

**Status Values**: `queued`, `importing`, `processing`, `completed`, `failed`

---

### crm_list_members

**Primary Writer**: selltonai-modal  
**Primary Readers**: selltonai-modal  
**Purpose**: Manual memberships for existing contacts/companies in CRM lists

| Column | Type | Constraints | Description | RLS |
|--------|------|-------------|-------------|-----|
| `id` | uuid | PK DEFAULT gen_random_uuid() | Membership ID | ✅ |
| `list_id` | uuid | NOT NULL, FK → crm_lists(id) | CRM list ID | ✅ |
| `organization_id` | text | NOT NULL, FK → organizations(id) | Owning organization | ✅ |
| `member_type` | text | NOT NULL | company, person | ✅ |
| `member_id` | uuid | NOT NULL | Company or contact ID | ✅ |
| `data` | jsonb | | Member data | ✅ |
| `created_at` | timestamptz | DEFAULT now() | Creation timestamp | ✅ |

**Member Type Values**: `company`, `person`

---

## Document & Email Tables

### organization_files

**Primary Writer**: selltonai-modal  
**Primary Readers**: selltonai, selltonai-vector-api  
**Purpose**: Uploaded documents for RAG and knowledge base

| Column | Type | Constraints | Description | RLS |
|--------|------|-------------|-------------|-----|
| `id` | uuid | PK DEFAULT gen_random_uuid() | File ID | ✅ |
| `organization_id` | text | NOT NULL, FK → organizations(id) | Owning organization | ✅ |
| `user_id` | text | | User who uploaded | ✅ |
| `file_name` | text | NOT NULL | Original file name | ✅ |
| `file_category` | text | NOT NULL | Category of file | ✅ |
| `file_path` | text | NOT NULL | Storage path | ✅ |
| `file_size` | bigint | | File size in bytes | ✅ |
| `mime_type` | text | | MIME type | ✅ |
| `metadata` | jsonb | | File metadata | ✅ |
| `processing_status` | text | DEFAULT 'pending' | File processing status | ✅ |
| `chunks_processed` | integer | DEFAULT 0 | Number of chunks processed | ✅ |
| `vector_indexed` | boolean | DEFAULT false | Whether vector embeddings indexed | ✅ |
| `created_at` | timestamptz | DEFAULT now() | Creation timestamp | ✅ |
| `updated_at` | timestamptz | DEFAULT now() | Last update timestamp | ✅ |

**File Category Values**:
`documents`, `transcripts`, `linkedin_voice`, `internal_documents`, `sales_papers`, `sait_guidelines`, `brand_guidelines`, `case_study`, `sales_scripts`

**Processing Status Values**: `pending`, `processing`, `completed`, `failed`

**Indexes**:
- `idx_organization_files_org_id` ON `organization_files(organization_id)`
- `idx_organization_files_user_id` ON `organization_files(user_id)`

---

### organization_files_chunks

**Primary Writer**: selltonai-modal  
**Primary Readers**: selltonai-modal, selltonai-vector-api  
**Purpose**: Document chunks for vector embeddings

| Column | Type | Constraints | Description | RLS |
|--------|------|-------------|-------------|-----|
| `id` | uuid | PK DEFAULT gen_random_uuid() | Chunk ID | ✅ |
| `organization_id` | text | NOT NULL, FK → organizations(id) | Owning organization | ✅ |
| `file_id` | uuid | NOT NULL, FK → organization_files(id) | Parent file ID | ✅ |
| `chunk_index` | integer | NOT NULL | Index of chunk in file | ✅ |
| `content` | text | NOT NULL | Chunk text content | ✅ |
| `token_count` | integer | | Number of tokens in chunk | ✅ |
| `embedding` | vector | | Vector embedding | ✅ |
| `metadata` | jsonb | | Chunk metadata | ✅ |
| `created_at` | timestamptz | DEFAULT now() | Creation timestamp | ✅ |

**Indexes**:
- `idx_organization_files_chunks_org_id` ON `organization_files_chunks(organization_id)`
- `idx_organization_files_chunks_file_id` ON `organization_files_chunks(file_id)`
- `idx_organization_files_chunks_chunk_index` ON `organization_files_chunks(file_id, chunk_index)`

---

### email_accounts

**Primary Writer**: selltonai-gmail-api  
**Primary Readers**: selltonai, selltonai-modal  
**Purpose**: Gmail OAuth tokens per org/user

| Column | Type | Constraints | Description | RLS |
|--------|------|-------------|-------------|-----|
| `id` | uuid | PK DEFAULT gen_random_uuid() | Account ID | ✅ |
| `organization_id` | text | NOT NULL, FK → organizations(id) | Owning organization | ✅ |
| `user_id` | text | | User ID | ✅ |
| `provider` | text | NOT NULL | gmail, outlook, imap | ✅ |
| `account_id` | text | | Provider account ID | ✅ |
| `credentials` | jsonb | | OAuth credentials | ✅ |
| `scopes` | text[] | | Granted scopes | ✅ |
| `is_connected` | boolean | DEFAULT false | Connection status | ✅ |
| `error` | text | | Connection error | ✅ |
| `created_at` | timestamptz | DEFAULT now() | Creation timestamp | ✅ |
| `updated_at` | timestamptz | DEFAULT now() | Last update timestamp | ✅ |

---

### email_tokens

**Primary Writer**: selltonai-modal  
**Primary Readers**: selltonai-modal, selltonai-gmail-api  
**Purpose**: Email token tracking

| Column | Type | Constraints | Description | RLS |
|--------|------|-------------|-------------|-----|
| `id` | uuid | PK DEFAULT gen_random_uuid() | Token ID | ✅ |
| `organization_id` | text | NOT NULL, FK → organizations(id) | Owning organization | ✅ |
| `token` | text | NOT NULL | Token value | ✅ |
| `token_type` | text | NOT NULL | Token type | ✅ |
| `metadata` | jsonb | | Token metadata | ✅ |
| `expires_at` | timestamptz | | Expiration timestamp | ✅ |
| `is_used` | boolean | DEFAULT false | Whether token has been used | ✅ |
| `created_at` | timestamptz | DEFAULT now() | Creation timestamp | ✅ |

---

### unmatched_replies

**Primary Writer**: selltonai-modal  
**Primary Readers**: backoffice  
**Purpose**: Incoming emails that could not be matched to a contact

| Column | Type | Constraints | Description | RLS |
|--------|------|-------------|-------------|-----|
| `id` | uuid | PK DEFAULT gen_random_uuid() | Reply ID | ✅ |
| `organization_id` | text | NOT NULL, FK → organizations(id) | Owning organization | ✅ |
| `email_id` | text | | Gmail email ID | ✅ |
| `thread_id` | text | | Gmail thread ID | ✅ |
| `account_id` | text | | Gmail account ID | ✅ |
| `from_email` | text | | Sender email | ✅ |
| `to_emails` | text[] | DEFAULT '{}' | Recipient emails | ✅ |
| `subject` | text | | Email subject | ✅ |
| `body` | text | | Email body | ✅ |
| `raw_payload` | jsonb | DEFAULT '{}' | Raw email payload | ✅ |
| `classification_snapshot` | jsonb | DEFAULT '{}' | Classification at time of receipt | ✅ |
| `resolution_status` | text | DEFAULT 'unmatched' | Resolution status | ✅ |
| `resolved_contact_id` | uuid | FK → contacts(id) | Matched contact ID | ✅ |
| `resolved_company_id` | uuid | FK → companies(id) | Matched company ID | ✅ |
| `resolved_campaign_id` | uuid | FK → campaigns(id) | Matched campaign ID | ✅ |
| `received_at` | timestamptz | DEFAULT now() | When email was received | ✅ |

**Resolution Status Values**: `unmatched`, `matched`, `ignored`

**Indexes**:
- `idx_unmatched_replies_org_id` ON `unmatched_replies(organization_id)`
- `idx_unmatched_replies_email_id` ON `unmatched_replies(email_id)` WHERE `email_id IS NOT NULL`
- `idx_unmatched_replies_status` ON `unmatched_replies(resolution_status)`

---

## Billing Tables

### billing_customers

**Primary Writer**: selltonai-modal  
**Primary Readers**: selltonai, backoffice  
**Purpose**: Workspace billing settings, monthly spend limits, and optional Stripe customer/payment details

| Column | Type | Constraints | Description | RLS |
|--------|------|-------------|-------------|-----|
| `id` | uuid | PK DEFAULT gen_random_uuid() | Customer ID | ✅ |
| `organization_id` | text | NOT NULL, FK → organizations(id) | Owning organization | ✅ |
| `stripe_customer_id` | text | | Stripe customer ID | ✅ |
| `subscription_id` | text | | Stripe subscription ID | ✅ |
| `billing_email` | text | | Billing email | ✅ |
| `billing_name` | text | | Billing name | ✅ |
| `billing_address` | jsonb | | Billing address | ✅ |
| `payment_method` | jsonb | | Payment method details | ✅ |
| `auto_charge` | boolean | DEFAULT true | Auto-charge enabled | ✅ |
| `monthly_spend_limit` | numeric | | Monthly spend limit | ✅ |
| `monthly_spend` | numeric | DEFAULT 0 | Current month spend | ✅ |
| `spend_resets_at` | timestamptz | | When spend resets | ✅ |
| `status` | text | | active, suspended, cancelled | ✅ |
| `metadata` | jsonb | | Additional metadata | ✅ |
| `created_at` | timestamptz | DEFAULT now() | Creation timestamp | ✅ |
| `updated_at` | timestamptz | DEFAULT now() | Last update timestamp | ✅ |

---

### billing_invoices

**Primary Writer**: selltonai-modal  
**Primary Readers**: selltonai, backoffice  
**Purpose**: Usage invoices, totals, Stripe invoice ids, and hosted invoice links

| Column | Type | Constraints | Description | RLS |
|--------|------|-------------|-------------|-----|
| `id` | uuid | PK DEFAULT gen_random_uuid() | Invoice ID | ✅ |
| `organization_id` | text | NOT NULL, FK → organizations(id) | Owning organization | ✅ |
| `billing_customer_id` | uuid | FK → billing_customers(id) | Billing customer reference | ✅ |
| `invoice_number` | text | | Human-readable invoice number | ✅ |
| `stripe_invoice_id` | text | | Stripe invoice ID | ✅ |
| `stripe_hosted_invoice_url` | text | | Stripe hosted invoice URL | ✅ |
| `period_start` | timestamptz | NOT NULL | Invoice period start | ✅ |
| `period_end` | timestamptz | NOT NULL | Invoice period end | ✅ |
| `amount_subtotal` | numeric | | Subtotal amount | ✅ |
| `amount_tax` | numeric | | Tax amount | ✅ |
| `amount_total` | numeric | | Total amount | ✅ |
| `currency` | text | DEFAULT 'usd' | Currency | ✅ |
| `description` | text | | Invoice description | ✅ |
| `status` | text | | draft, open, paid, void, uncollectible | ✅ |
| `payment_status` | text | | paid, unpaid, partially_paid | ✅ |
| `due_date` | timestamptz | | Payment due date | ✅ |
| `paid_at` | timestamptz | | When payment was received | ✅ |
| `metadata` | jsonb | | Additional metadata | ✅ |
| `created_at` | timestamptz | DEFAULT now() | Creation timestamp | ✅ |
| `updated_at` | timestamptz | DEFAULT now() | Last update timestamp | ✅ |

---

### billing_invoice_sequences

**Primary Writer**: selltonai-modal  
**Primary Readers**: selltonai-modal  
**Purpose**: Year-scoped reservation state for explicit Stripe invoice numbers

| Column | Type | Constraints | Description | RLS |
|--------|------|-------------|-------------|-----|
| `id` | uuid | PK DEFAULT gen_random_uuid() | Sequence ID | ✅ |
| `year` | integer | NOT NULL | Year | ✅ |
| `next_invoice_number` | integer | NOT NULL | Next invoice number | ✅ |
| `created_at` | timestamptz | DEFAULT now() | Creation timestamp | ✅ |
| `updated_at` | timestamptz | DEFAULT now() | Last update timestamp | ✅ |

---

### usage

**Primary Writer**: selltonai-modal  
**Primary Readers**: selltonai, backoffice  
**Purpose**: Billable usage rows linked to generated invoices

| Column | Type | Constraints | Description | RLS |
|--------|------|-------------|-------------|-----|
| `id` | uuid | PK DEFAULT gen_random_uuid() | Usage ID | ✅ |
| `organization_id` | text | NOT NULL, FK → organizations(id) | Owning organization | ✅ |
| `billing_invoice_id` | uuid | FK → billing_invoices(id) | Invoice reference | ✅ |
| `billing_customer_id` | uuid | FK → billing_customers(id) | Customer reference | ✅ |
| `usage_type` | text | NOT NULL | Type of usage | ✅ |
| `amount` | numeric | NOT NULL | Usage amount | ✅ |
| `unit_price` | numeric | NOT NULL | Price per unit | ✅ |
| `total_price` | numeric | NOT NULL | Total price | ✅ |
| `metadata` | jsonb | | Usage metadata | ✅ |
| `period_start` | timestamptz | | Usage period start | ✅ |
| `period_end` | timestamptz | | Usage period end | ✅ |
| `created_at` | timestamptz | DEFAULT now() | Creation timestamp | ✅ |

---

## AI & Research Tables

### onboarding_research

**Primary Writer**: selltonai-modal  
**Primary Readers**: selltonai-modal, selltonai, backoffice  
**Purpose**: V1/V2 onboarding research state

| Column | Type | Constraints | Description | RLS |
|--------|------|-------------|-------------|-----|
| `id` | uuid | PK DEFAULT gen_random_uuid() | Research record ID | ✅ |
| `organization_id` | text | NOT NULL, FK → organizations(id) | Owning organization | ✅ |
| `user_id` | text | | User who initiated onboarding | ✅ |
| `company_website` | text | | Company website URL | ✅ |
| `company_name_hint` | text | | Company name hint | ✅ |
| `retell_call_id` | text | | Retell call ID | ✅ |
| `status` | text | | Current research status | ✅ |
| `company_name` | text | | Extracted company name | ✅ |
| `company_website` | text | | Normalized company website | ✅ |
| `company_linkedin_url` | text | | Company LinkedIn URL | ✅ |
| `company_description` | text | | Company description | ✅ |
| `industries` | text[] | | Company industries | ✅ |
| `core_offer` | jsonb | | Core product/service offering | ✅ |
| `value_propositions` | jsonb | | Value propositions | ✅ |
| `use_cases` | jsonb | | Use cases | ✅ |
| `icp_hypotheses` | jsonb | | ICP hypotheses | ✅ |
| `buyer_roles` | text[] | | Target buyer roles | ✅ |
| `competitors` | text[] | | Company competitors | ✅ |
| `partnerships` | text[] | | Company partnerships | ✅ |
| `discovery_questions` | text[] | | Discovery questions | ✅ |
| `evidence_sources` | jsonb | | Sources used for research | ✅ |
| `discovery_metadata` | jsonb | | Research metadata | ✅ |
| `v2_*` | text/jsonb | | V2 onboarding fields | ✅ |
| `approved_at` | timestamptz | | When V2 was approved | ✅ |
| `cascade_started_at` | timestamptz | | When cascade to KB started | ✅ |
| `cascade_completed_at` | timestamptz | | When cascade completed | ✅ |
| `created_at` | timestamptz | DEFAULT now() | Creation timestamp | ✅ |
| `updated_at` | timestamptz | DEFAULT now() | Last update timestamp | ✅ |

**Status Values**: `not_started`, `researching`, `research_complete`, `v2_generating`, `v2_complete`, `cascade_started`, `cascade_complete`, `approved`

**Indexes**:
- `idx_onboarding_research_org_id` ON `onboarding_research(organization_id)`
- `idx_onboarding_research_status` ON `onboarding_research(status)`

---

### sender_voice

**Primary Writer**: selltonai-modal  
**Primary Readers**: selltonai  
**Purpose**: Per-user LinkedIn writing voice distilled from Retell

| Column | Type | Constraints | Description | RLS |
|--------|------|-------------|-------------|-----|
| `id` | uuid | PK DEFAULT gen_random_uuid() | Voice record ID | ✅ |
| `organization_id` | text | NOT NULL, FK → organizations(id) | Owning organization | ✅ |
| `user_id` | text | | User who provided voice | ✅ |
| `linkedin_account_id` | uuid | | LinkedIn account reference | ✅ |
| `retell_call_id` | text | | Retell call ID | ✅ |
| `content` | jsonb | | Distilled voice content | ✅ |
| `metadata` | jsonb | | Processing metadata | ✅ |
| `created_at` | timestamptz | DEFAULT now() | Creation timestamp | ✅ |
| `updated_at` | timestamptz | DEFAULT now() | Last update timestamp | ✅ |

---

### avatar_interviews

**Primary Writer**: selltonai  
**Primary Readers**: selltonai-modal, selltonai  
**Purpose**: Retell call tracking for onboarding and sender voice

| Column | Type | Constraints | Description | RLS |
|--------|------|-------------|-------------|-----|
| `id` | uuid | PK DEFAULT gen_random_uuid() | Interview ID | ✅ |
| `organization_id` | text | NOT NULL, FK → organizations(id) | Owning organization | ✅ |
| `user_id` | text | | User who participated | ✅ |
| `call_type` | text | | onboarding, linkedin_voice, sender_voice | ✅ |
| `retell_call_id` | text | | Retell call ID | ✅ |
| `transcript` | text | | Call transcript | ✅ |
| `recording_url` | text | | Recording URL | ✅ |
| `status` | text | | pending, completed, failed | ✅ |
| `metadata` | jsonb | | Call metadata | ✅ |
| `created_at` | timestamptz | DEFAULT now() | Creation timestamp | ✅ |
| `updated_at` | timestamptz | DEFAULT now() | Last update timestamp | ✅ |

---

### style_guidelines

**Primary Writer**: selltonai-modal  
**Primary Readers**: selltonai  
**Purpose**: Writing style guidelines from documents

| Column | Type | Constraints | Description | RLS |
|--------|------|-------------|-------------|-----|
| `id` | uuid | PK DEFAULT gen_random_uuid() | Guidelines ID | ✅ |
| `organization_id` | text | NOT NULL, FK → organizations(id) | Owning organization | ✅ |
| `brand_voice` | jsonb | | Brand voice guidelines | ✅ |
| `tone` | text | | Writing tone | ✅ |
| `style_points` | text[] | | Style points | ✅ |
| `avoid` | text[] | | Words/phrases to avoid | ✅ |
| `preferred_terms` | jsonb | | Preferred terminology | ✅ |
| `document_id` | uuid | | Source document ID | ✅ |
| `created_at` | timestamptz | DEFAULT now() | Creation timestamp | ✅ |
| `updated_at` | timestamptz | DEFAULT now() | Last update timestamp | ✅ |

---

### deep_research_settings

**Primary Writer**: selltonai-modal  
**Primary Readers**: selltonai-modal  
**Purpose**: Org-level research provider settings

| Column | Type | Constraints | Description | RLS |
|--------|------|-------------|-------------|-----|
| `id` | uuid | PK DEFAULT gen_random_uuid() | Settings ID | ✅ |
| `organization_id` | text | NOT NULL, FK → organizations(id) | Owning organization | ✅ |
| `provider` | text | | none, exa, perplexity, gemini | ✅ |
| `research_types` | text[] | | Enabled research types | ✅ |
| `created_at` | timestamptz | DEFAULT now() | Creation timestamp | ✅ |
| `updated_at` | timestamptz | DEFAULT now() | Last update timestamp | ✅ |

---

### ai_ark_enrollment_runs

**Primary Writer**: selltonai-modal  
**Primary Readers**: backoffice/support  
**Purpose**: Idempotency ledger for AI-Ark enrollment recovery

| Column | Type | Constraints | Description | RLS |
|--------|------|-------------|-------------|-----|
| `id` | uuid | PK DEFAULT gen_random_uuid() | Run ID | ✅ |
| `enrollment_id` | text | NOT NULL | AI-Ark enrollment ID | ✅ |
| `campaign_id` | uuid | NOT NULL, FK → campaigns(id) | Campaign reference | ✅ |
| `company_id` | uuid | NOT NULL, FK → companies(id) | Company reference | ✅ |
| `organization_id` | text | NOT NULL, FK → organizations(id) | Owning organization | ✅ |
| `status` | text | NOT NULL DEFAULT 'running' | Run status | ✅ |
| `result_count` | integer | NOT NULL DEFAULT 0 | Number of results | ✅ |
| `error_message` | text | | Error if failed | ✅ |
| `run_at` | timestamptz | DEFAULT now() | When run started | ✅ |
| `updated_at` | timestamptz | DEFAULT now() | Last update | ✅ |

**Status Values**: `running`, `completed`, `failed`

**Unique**: `(enrollment_id, company_id)` prevents duplicate searches

---

### organization_onboarding_events

**Primary Writer**: selltonai, selltonai-modal  
**Primary Readers**: selltonai, backoffice  
**Purpose**: Funnel transition audit log

| Column | Type | Constraints | Description | RLS |
|--------|------|-------------|-------------|-----|
| `id` | uuid | PK DEFAULT gen_random_uuid() | Event ID | ✅ |
| `organization_id` | text | NOT NULL, FK → organizations(id) | Owning organization | ✅ |
| `user_id` | text | | User who triggered event | ✅ |
| `event_type` | text | NOT NULL | Type of onboarding event | ✅ |
| `from_phase` | text | | Previous phase | ✅ |
| `to_phase` | text | | New phase | ✅ |
| `metadata` | jsonb | | Additional event data | ✅ |
| `created_at` | timestamptz | DEFAULT now() | Event timestamp | ✅ |

**Event Type Values**:
`phase_transition`, `onboarding_started`, `research_completed`, `first_campaign_created`, `onboarding_completed`

---

## LinkedIn Integration Tables

### linkedin_accounts

**Primary Writer**: selltonai-modal  
**Primary Readers**: selltonai-modal, backoffice  
**Purpose**: LinkedIn account connections

| Column | Type | Constraints | Description | RLS |
|--------|------|-------------|-------------|-----|
| `id` | uuid | PK DEFAULT gen_random_uuid() | Account ID | ✅ |
| `organization_id` | text | NOT NULL, FK → organizations(id) | Owning organization | ✅ |
| `user_id` | text | | User who connected account | ✅ |
| `linkedin_id` | text | | LinkedIn account ID | ✅ |
| `access_token` | text | | OAuth access token | ✅ |
| `refresh_token` | text | | OAuth refresh token | ✅ |
| `expires_at` | timestamptz | | Token expiration | ✅ |
| `scopes` | text[] | | Granted scopes | ✅ |
| `is_active` | boolean | DEFAULT true | Account active status | ✅ |
| `subscription_type` | text | | Account subscription type | ✅ |
| `profile` | jsonb | | LinkedIn profile data | ✅ |
| `metadata` | jsonb | | Account metadata | ✅ |
| `created_at` | timestamptz | DEFAULT now() | Creation timestamp | ✅ |
| `updated_at` | timestamptz | DEFAULT now() | Last update timestamp | ✅ |

---

### linkedin_action_log

**Primary Writer**: selltonai-modal  
**Primary Readers**: selltonai-modal, backoffice  
**Purpose**: LinkedIn action history with idempotency

| Column | Type | Constraints | Description | RLS |
|--------|------|-------------|-------------|-----|
| `id` | uuid | PK DEFAULT gen_random_uuid() | Log ID | ✅ |
| `organization_id` | text | NOT NULL, FK → organizations(id) | Owning organization | ✅ |
| `campaign_id` | uuid | FK → campaigns(id) | Campaign reference | ✅ |
| `linkedin_account_id` | uuid | FK → linkedin_accounts(id) | LinkedIn account | ✅ |
| `action_type` | text | NOT NULL | Action performed | ✅ |
| `action_data` | jsonb | | Action data | ✅ |
| `status` | text | | pending, completed, failed, skipped | ✅ |
| `idempotency_key` | text | | Idempotency key | ✅ |
| `error_message` | text | | Error if failed | ✅ |
| `retry_count` | integer | DEFAULT 0 | Retry count | ✅ |
| `scheduled_for` | timestamptz | | Scheduled execution time | ✅ |
| `executed_at` | timestamptz | | When executed | ✅ |
| `completed_at` | timestamptz | | When completed | ✅ |
| `metadata` | jsonb | | Additional metadata | ✅ |
| `created_at` | timestamptz | DEFAULT now() | Creation timestamp | ✅ |
| `updated_at` | timestamptz | DEFAULT now() | Last update timestamp | ✅ |

**Action Type Values**:
`message_send`, `profile_visit`, `connection_request`, `follow`, `react`, `comment`, `share`

**Indexes**:
- `idx_linkedin_action_log_org_id` ON `linkedin_action_log(organization_id)`
- `idx_linkedin_action_log_campaign_id` ON `linkedin_action_log(campaign_id)` WHERE `campaign_id IS NOT NULL`
- `idx_linkedin_action_log_account_id` ON `linkedin_action_log(linkedin_account_id)`
- `idx_linkedin_action_log_idempotency` ON `linkedin_action_log(idempotency_key)` WHERE `idempotency_key IS NOT NULL`
- `idx_linkedin_action_log_status` ON `linkedin_action_log(status)`

---

### linkedin_threads

**Primary Writer**: selltonai-modal  
**Primary Readers**: selltonai-modal, backoffice  
**Purpose**: LinkedIn conversation threads

| Column | Type | Constraints | Description | RLS |
|--------|------|-------------|-------------|-----|
| `id` | uuid | PK DEFAULT gen_random_uuid() | Thread ID | ✅ |
| `organization_id` | text | NOT NULL, FK → organizations(id) | Owning organization | ✅ |
| `campaign_id` | uuid | FK → campaigns(id) | Campaign reference | ✅ |
| `linkedin_thread_id` | text | NOT NULL | LinkedIn thread ID | ✅ |
| `subject` | text | | Thread subject | ✅ |
| `participants` | jsonb | | Thread participants | ✅ |
| `status` | text | DEFAULT 'active' | Thread status | ✅ |
| `last_message_at` | timestamptz | | Last message timestamp | ✅ |
| `message_count` | integer | DEFAULT 0 | Number of messages | ✅ |
| `metadata` | jsonb | | Thread metadata | ✅ |
| `created_at` | timestamptz | DEFAULT now() | Creation timestamp | ✅ |
| `updated_at` | timestamptz | DEFAULT now() | Last update timestamp | ✅ |

**Indexes**:
- `idx_linkedin_threads_org_id` ON `linkedin_threads(organization_id)`
- `idx_linkedin_threads_campaign_id` ON `linkedin_threads(campaign_id)` WHERE `campaign_id IS NOT NULL`
- `idx_linkedin_threads_linkedin_id` ON `linkedin_threads(linkedin_thread_id)`
- `idx_linkedin_threads_status` ON `linkedin_threads(status)`

---

### linkedin_messages

**Primary Writer**: selltonai-modal  
**Primary Readers**: selltonai-modal, backoffice  
**Purpose**: LinkedIn messages in threads

| Column | Type | Constraints | Description | RLS |
|--------|------|-------------|-------------|-----|
| `id` | uuid | PK DEFAULT gen_random_uuid() | Message ID | ✅ |
| `organization_id` | text | NOT NULL, FK → organizations(id) | Owning organization | ✅ |
| `thread_id` | uuid | NOT NULL, FK → linkedin_threads(id) | Thread reference | ✅ |
| `linkedin_message_id` | text | NOT NULL | LinkedIn message ID | ✅ |
| `sender_id` | text | | LinkedIn sender ID | ✅ |
| `body` | text | | Message body | ✅ |
| `is_from_us` | boolean | | Whether sent from Sellton | ✅ |
| `sentiment` | text | | Message sentiment | ✅ |
| `intent` | jsonb | | Message intent classification | ✅ |
| `metadata` | jsonb | | Message metadata | ✅ |
| `created_at` | timestamptz | DEFAULT now() | Creation timestamp | ✅ |

**Indexes**:
- `idx_linkedin_messages_org_id` ON `linkedin_messages(organization_id)`
- `idx_linkedin_messages_thread_id` ON `linkedin_messages(thread_id)`
- `idx_linkedin_messages_linkedin_id` ON `linkedin_messages(linkedin_message_id)`

---

### provider_event_log

**Primary Writer**: selltonai-modal  
**Primary Readers**: backoffice/support  
**Purpose**: Provider event tracking for debugging

| Column | Type | Constraints | Description | RLS |
|--------|------|-------------|-------------|-----|
| `id` | uuid | PK DEFAULT gen_random_uuid() | Event ID | ✅ |
| `organization_id` | text | FK → organizations(id) | Owning organization | ✅ |
| `provider` | text | NOT NULL | AI provider name | ✅ |
| `event_type` | text | NOT NULL | Type of event | ✅ |
| `request_id` | text | | Request ID for correlation | ✅ |
| `data` | jsonb | | Event data | ✅ |
| `error` | text | | Error if applicable | ✅ |
| `processed` | boolean | DEFAULT false | Whether event was processed | ✅ |
| `created_at` | timestamptz | DEFAULT now() | Event timestamp | ✅ |

**Indexes**:
- `idx_provider_event_log_org_id` ON `provider_event_log(organization_id)` WHERE `organization_id IS NOT NULL`
- `idx_provider_event_log_provider` ON `provider_event_log(provider)`
- `idx_provider_event_log_event_type` ON `provider_event_log(event_type)`
- `idx_provider_event_log_created_at` ON `provider_event_log(created_at)`
- `idx_provider_event_log_processed` ON `provider_event_log(processed)`

---

## Enum Types

### company_processing_status

```sql
CREATE TYPE company_processing_status AS ENUM (
  'scheduled',      -- Ready to be processed
  'processing',     -- Currently being processed
  'processed',      -- Processing completed successfully
  'failed',         -- Processing failed
  'blocked_by_icp', -- Blocked by ICP filter
  'imported'        -- Imported from CRM (not via campaign)
);
```

### pipeline_stage

```sql
CREATE TYPE pipeline_stage AS ENUM (
  'prospect',              -- New lead
  'appointment_requested', -- Appointment requested
  'qualified',             -- Qualified lead
  'proposal',              -- Proposal sent
  'negotiation',           -- Negotiating
  'won',                   -- Won deal
  'lost',                  -- Lost deal
  'not_interested'         -- Not interested
);
```

### task_type

```sql
CREATE TYPE task_type AS ENUM (
  'company_verification', -- Verify company data
  'email_copy',           -- Write email copy
  'call_script',          -- Prepare call script
  'follow_up_email'       -- Follow-up email
);
```

### task_status

```sql
CREATE TYPE task_status AS ENUM (
  'pending',    -- Not yet reviewed
  'approved',   -- Approved and ready
  'rejected',   -- Rejected by user
  'completed',  -- Completed
  'cancelled'   -- Cancelled
);
```

### email_search_status

```sql
CREATE TYPE email_search_status AS ENUM (
  'search_not_started',    -- Not yet started
  'searching',            -- Currently searching
  'finished_searching_email' -- Search completed
);
```

### Additional Enums

| Type | Values |
|------|--------|
| `record_type` | `unknown`, `company`, `person` |
| `import_status` | `raw`, `extracted`, `failed` |
| `campaign_status` | `draft`, `active`, `paused`, `discovery_completed`, `completed`, `fully_completed`, `cancelled` |
| `lead_source` | `csv`, `template_csv`, `crm_list`, `manual`, `b2b_search`, `research` |
| `priority` | `low`, `normal`, `high`, `urgent` |

---

## RLS Policies

### Policy Template

All public tables have RLS policies following this pattern:

```sql
-- Enable RLS
ALTER TABLE table_name ENABLE ROW LEVEL SECURITY;

-- SELECT policy
CREATE POLICY "Users can view their organization's data"
  ON table_name FOR SELECT
  USING (organization_id = current_setting('app.current_org_id', true));

-- INSERT policy
CREATE POLICY "Users can insert data for their organization"
  ON table_name FOR INSERT
  WITH CHECK (organization_id = current_setting('app.current_org_id', true));

-- UPDATE policy
CREATE POLICY "Users can update their organization's data"
  ON table_name FOR UPDATE
  USING (organization_id = current_setting('app.current_org_id', true));

-- DELETE policy
CREATE POLICY "Users can delete their organization's data"
  ON table_name FOR DELETE
  USING (organization_id = current_setting('app.current_org_id', true));
```

### Custom Policies

Some tables have additional or custom policies:

#### users Table
```sql
-- Users can view their own profile
CREATE POLICY "Users can view own profile"
  ON users FOR SELECT
  USING (id = current_setting('app.current_user_id'));

-- Users can update their own profile
CREATE POLICY "Users can update own profile"
  ON users FOR UPDATE
  USING (id = current_setting('app.current_user_id'));
```

#### organization_settings Table
```sql
-- Only one row per organization
CREATE POLICY "One settings row per organization"
  ON organization_settings FOR INSERT
  WITH CHECK (
    NOT EXISTS (
      SELECT 1 FROM organization_settings 
      WHERE organization_id = current_setting('app.current_org_id', true)
    )
  );
```

---

## Indexes

### Current Index Inventory

The database has ~100+ indexes for performance. Key indexes include:

#### Organization-Scoped Indexes
- `idx_*_organization_id` - Filter by organization
- `idx_*_org_status` - Filter by organization and status
- `idx_*_org_created_at` - Filter by organization and creation time

#### Status-Based Indexes
- `idx_*_status` - Filter by status
- `idx_*_processing_status` - Company processing status
- `idx_*_pipeline_stage` - Contact pipeline stage
- `idx_*_import_status` - CRM import status

#### Relationship Indexes
- `idx_*_campaign_id` - Filter by campaign
- `idx_*_company_id` - Filter by company
- `idx_*_contact_id` - Filter by contact
- `idx_*_user_id` - Filter by user
- `idx_*_list_id` - Filter by list

#### Partial Indexes
- `idx_*_WHERE column IS NOT NULL` - Only index non-null values
- `idx_*_WHERE status = 'pending'` - Only index pending items

#### GIN Indexes (for JSONB)
- `idx_companies_icp_score_gin` - Query within icp_score JSONB

### Index Creation Pattern

```sql
-- Standard B-tree index
CREATE INDEX idx_table_column ON table(column);

-- Compound index
CREATE INDEX idx_table_col1_col2 ON table(col1, col2);

-- Partial index
CREATE INDEX idx_table_column_where ON table(column) WHERE column IS NOT NULL;

-- Unique index
CREATE UNIQUE INDEX idx_table_unique ON table(col1, col2);

-- GIN index for JSONB
CREATE INDEX idx_table_jsonb_gin ON table USING GIN (jsonb_column);

-- Add comment
COMMENT ON INDEX idx_table_column IS 'Index for filtering by column';
```

---

## JSONB Schemas

### companies Table JSONB Fields

#### b2b_result
```json
{
  "id": "string",
  "name": "string",
  "website": "string",
  "linkedin_url": "string",
  "employee_count": 150,
  "industries": ["Software", "SaaS"],
  "description": "string",
  "phone": "string",
  "location": "string",
  "founded_year": 2010,
  "followers": 10000,
  "size": "string",
  "specialities": ["string"],
  "hashtags": ["string"],
  "raw_data": {}
}
```

#### b2b_enrichment
```json
{
  "enriched_at": "2026-01-01T00:00:00Z",
  "provider": "ai_ark",
  "confidence": 0.95,
  "data": {
    "name": "string",
    "website": "string",
    "linkedin_url": "string",
    "employee_count": 150,
    "industries": ["Software"],
    "description": "string",
    "phone": "string",
    "location": "string",
    "founded_year": 2010,
    "revenue": "$10M",
    "keywords": ["string"]
  }
}
```

#### icp_score
```json
{
  "score": 85,
  "grade": "A",
  "reasons": ["Good size match", "Right industry"],
  "calculated_at": "2026-01-01T00:00:00Z",
  "model": "v3",
  "thresholds": {
    "A": 80,
    "B": 60,
    "C": 40,
    "D": 20
  }
}
```

#### deep_research
```json
{
  "company_overview": "string",
  "technology_stack": ["string"],
  "recent_news": [
    {
      "title": "string",
      "url": "string",
      "summary": "string",
      "published_at": "string"
    }
  ],
  "competitors": ["string"],
  "partnerships": ["string"],
  "financials": {
    "revenue": "string",
    "funding": "string",
    "last_funding_round": "string"
  },
  "provider": "exa",
  "model": "string",
  "processed_at": "2026-01-01T00:00:00Z"
}
```

#### outreach_strategy
```json
{
  "strategy": "string",
  "value_propositions": [
    {
      "claim": "string",
      "evidence": "string",
      "confidence": 0.8
    }
  ],
  "pain_points": ["string"],
  "use_cases": [
    {
      "name": "string",
      "description": "string",
      "buyer_or_user": "string"
    }
  ],
  "icp_hypotheses": [
    {
      "segment": "string",
      "why_it_fits": "string",
      "likely_pain_points": ["string"],
      "confidence": 0.7
    }
  ],
  "buyer_roles": ["string"],
  "discovery_questions": ["string"],
  "generated_at": "2026-01-01T00:00:00Z"
}
```

---

## Data Lifecycle

### Campaign Lifecycle
```
Created (draft) → Started (active) → Processing (cron) → Completed
                                                    ↓
                                              Tasks created
                                                    ↓
                                            Emails sent
                                                    ↓
                                          Stats aggregated
```

### Company Processing Lifecycle
```
Scheduled → Processing → Processed (success)
                    → Failed (error)
                    → Blocked (ICP filter)
                    → Imported (from CRM)
```

**Processing Steps (CompanyProcessServiceV3)**:
1. Company data extraction
2. B2B enrichment
3. ICP scoring
4. Contact discovery
5. Contact enrichment
6. Verification task creation

### CRM Import Lifecycle
```
CSV Upload → Raw records (unknown) → Processing → Extracted
                                                ↓
                                      Companies + Contacts created
                                                ↓
                                      Relationships linked
```

**Large CSV Import Phases**:
```
queued → importing/raw_import → processing/classification
                                → processing/companies
                                → processing/contacts
                                → processing/relationships
                                → completed
                                → failed
```

### Task Lifecycle
```
Pending → Approved → (work performed) → Completed
                → Rejected
                → Cancelled
```

### Onboarding Lifecycle
```
not_started → research_started → research_v2_generating → cascade_started → cascade_complete → kb_built → first_campaign_created → launched
```

---

## Cross-Reference: Service Ownership

For complete table ownership and access patterns, see:
- [Cross-Project Documentation](docs/cross-project/README.md)

Each table has a **Primary Writer** responsible for:
- Schema changes (migrations)
- Data integrity
- Write operations
- API endpoints (if applicable)

**Primary Writers by Service**:
- **selltonai-modal**: campaigns, companies, contacts, tasks, onboarding_research, etc.
- **backoffice**: organization_settings, users (admin)
- **selltonai-crawler**: companies (enrichment), contacts (enrichment)
- **selltonai-gmail-api**: email_accounts, email_tokens, unmatched_replies
- **selltonai-vector-api**: organization_files_chunks (reads from organization_files)

---

## Data Validation Rules

1. **Organization Isolation**: All queries must filter by `organization_id`
2. **RLS Enforcement**: Frontend always uses anon key (RLS enforced)
3. **Service Role**: Backend uses service role key (RLS bypassed)
4. **JSONB Validation**: Application code validates JSONB structures
5. **Enum Validation**: Application code validates enum values
6. **Foreign Keys**: Database enforces referential integrity
7. **Unique Constraints**: Database enforces uniqueness

**Critical**: Always set `app.current_org_id` before making queries from frontend services.
