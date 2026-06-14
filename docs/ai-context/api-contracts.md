# API Contracts - Supabase

## Overview

This document defines the API contracts and service-level agreements for the Supabase database infrastructure. Unlike application-level APIs, the Supabase project provides **database-level APIs** that all Sellton services consume.

The Supabase project exposes:
1. **REST API** - HTTP endpoints for database operations
2. **Realtime API** - WebSocket-based realtime subscriptions
3. **Storage API** - File storage operations
4. **Authentication API** - JWT-based authentication (via Clerk integration)

---

## Service Endpoints

### REST API Base URLs

| Environment | Base URL | Access Key |
|-------------|----------|------------|
| **Development** (local) | `http://localhost:54321/rest/v1` | `eyJ...` (anon key) |
| **Development** (remote) | `https://xxx.supabase.co/rest/v1` | `eyJ...` (anon key) |
| **Production** | `https://xxx.supabase.co/rest/v1` | `eyJ...` (anon key) |

### Authentication

Supabase uses **Bearer Token** authentication:

```http
Authorization: Bearer <SUPABASE_ANON_KEY>
apikey: <SUPABASE_ANON_KEY>
```

For backend services using service role key:

```http
Authorization: Bearer <SUPABASE_SERVICE_ROLE_KEY>
apikey: <SUPABASE_SERVICE_ROLE_KEY>
```

### Required Headers

```http
Content-Type: application/json
Prefer: return=representation  # Return full record on insert
```

---

## REST API Contracts

### Query Pattern

All REST API requests follow this pattern:

```http
GET /rest/v1/<table_or_view>?<filters>&<options>
```

### Filters

| Operator | Syntax | Example |
|----------|--------|---------|
| Equal | `column=eq.value` | `organization_id=eq.org_123` |
| Not Equal | `column=neq.value` | `status=neq.failed` |
| Greater Than | `column=gt.value` | `created_at=gt.2026-01-01` |
| Greater Than or Equal | `column=gte.value` | `created_at=gte.2026-01-01` |
| Less Than | `column=lt.value` | `created_at=lt.2026-02-01` |
| Less Than or Equal | `column=lte.value` | `created_at=lte.2026-02-01` |
| Like | `column=like.*value*` | `name=like.*Acme*` |
| ILike | `column=ilike.*value*` | `name=ilike.*acme*` (case-insensitive) |
| Is Null | `column=is.null` | `deleted_at=is.null` |
| Is Not Null | `column=is.not.null` | `email=is.not.null` |
| In | `column=in.(val1,val2)` | `status=in.(active,completed)` |
| Contains (JSONB) | `column=cs.{"key":"value"}` | `metadata=cs.{"source":"api"}` |
| Contains (Array) | `column=cs.{value}` | `industries=cs.{SaaS}` |

### Modifiers

| Modifier | Syntax | Example |
|----------|--------|---------|
| Order | `order=column.asc` | `order=created_at.desc` |
| Limit | `limit=N` | `limit=100` |
| Offset | `offset=N` | `offset=50` |
| Select | `select=col1,col2` | `select=id,name,email` |

### Example Queries

#### Get Organization Campaigns

```http
GET /rest/v1/campaigns?organization_id=eq.org_123&status=eq.active&order=created_at.desc&limit=50
Authorization: Bearer <ANON_KEY>
apikey: <ANON_KEY>
```

**Response**:
```json
{
  "data": [
    {
      "id": "uuid-123",
      "organization_id": "org_123",
      "name": "Q2 Outreach",
      "status": "active",
      "total_companies": 50,
      "created_at": "2026-04-01T10:00:00Z"
    },
    {
      "id": "uuid-456",
      "organization_id": "org_123",
      "name": "Q1 Campaign",
      "status": "active",
      "total_companies": 100,
      "created_at": "2026-03-15T14:30:00Z"
    }
  ],
  "count": 2,
  "count_exact": true
}
```

#### Get Companies with ICP Score

```http
GET /rest/v1/companies?organization_id=eq.org_123&processing_status=eq.processed&order=icp_score->>score.desc&limit=20
```

#### Get Contacts by Pipeline Stage

```http
GET /rest/v1/contacts?organization_id=eq.org_123&pipeline_stage=eq.qualified&order=created_at.desc
```

#### Search Companies by Name

```http
GET /rest/v1/companies?organization_id=eq.org_123&name=ilike.*acme*&limit=10
```

---

## RPC (Remote Procedure Calls)

### Setting Organization Context

Before making queries, frontend services must set the current organization:

```http
POST /rest/v1/rpc/set_current_org_id
Authorization: Bearer <ANON_KEY>
apikey: <ANON_KEY>
Content-Type: application/json

{
  "org_id": "org_123"
}
```

**Response**:
```json
{
  "data": [
    {
      "set_current_org_id": "org_123"
    }
  ]
}
```

**Important**: This setting is used by RLS policies to filter data.

### Custom RPC Functions

The database includes custom PostgreSQL functions exposed via RPC:

#### Get Organization Stats

```http
POST /rest/v1/rpc/get_organization_stats
Content-Type: application/json

{
  "org_id": "org_123"
}
```

**Response**:
```json
{
  "data": [
    {
      "total_campaigns": 5,
      "total_companies": 250,
      "total_contacts": 500,
      "active_campaigns": 2,
      "pending_tasks": 15,
      "processing_companies": 10
    }
  ]
}
```

#### Check Billing Status

```http
POST /rest/v1/rpc/check_billing_status
Content-Type: application/json

{
  "org_id": "org_123"
}
```

---

## Realtime API Contracts

### Connection

```javascript
// Client-side connection
const supabase = createClient(
  import.meta.env.VITE_SUPABASE_URL,
  import.meta.env.VITE_SUPABASE_ANON_KEY
);

// Subscribe to table changes
const channel = supabase
  .channel(`table_db_changes`)
  .on(
    'postgres_changes',
    {
      event: '*',
      schema: 'public',
      table: 'campaigns',
      filter: `organization_id=eq.org_123`
    },
    (payload) => {
      console.log('Change:', payload);
    }
  )
  .subscribe();
```

### Payload Structure

```json
{
  "schema": "public",
  "table": "campaigns",
  "commit_timestamp": "2026-04-01T10:00:00Z",
  "event_type": "INSERT" | "UPDATE" | "DELETE",
  "new": {                  // For INSERT and UPDATE
    "id": "uuid-123",
    "name": "New Campaign",
    "status": "active",
    "organization_id": "org_123",
    "created_at": "2026-04-01T10:00:00Z"
  },
  "old": {                  // For UPDATE and DELETE
    "id": "uuid-123",
    "name": "Old Name",
    "status": "draft"
  },
  "changes": {              // For UPDATE only
    "name": {"old": "Old Name", "new": "New Campaign"},
    "status": {"old": "draft", "new": "active"}
  }
}
```

### Realtime Channels

| Channel | Purpose | Typical Usage |
|---------|---------|---------------|
| `campaigns_<org_id>` | Campaign updates | selltonai campaign list |
| `companies_<org_id>` | Company updates | selltonai company list |
| `tasks_<org_id>` | Task creation | selltonai task inbox |
| `onboarding_<org_id>` | Onboarding progress | sellton-onboard status |
| `billing_<org_id>` | Billing updates | backoffice dashboard |

### Broadcast Messages

Services can broadcast custom messages:

```javascript
// Send broadcast
const channel = supabase.channel('custom_broadcast');
channel.send({
  type: 'broadcast',
  event: 'refresh_cache',
  payload: { cache_key: 'campaigns' }
});

// Receive broadcast
const channel = supabase
  .channel('custom_broadcast')
  .on('broadcast', { event: 'refresh_cache' }, (payload) => {
    console.log('Refresh cache:', payload);
  })
  .subscribe();
```

---

## Storage API Contracts

### Upload File

```http
POST /storage/v1/object/<bucket_name>/<path>
Authorization: Bearer <ANON_KEY>
apikey: <ANON_KEY>
Content-Type: multipart/form-data

-- file data
```

**Example**:
```javascript
const { data, error } = await supabase
  .storage
  .from('organization_files')
  .upload(`org_123/${fileId}.pdf`, file, {
    cacheControl: '3600',
    upsert: false
  });
```

### Download File

```http
GET /storage/v1/object/<bucket_name>/<path>
Authorization: Bearer <ANON_KEY>
apikey: <ANON_KEY>
```

**Example**:
```javascript
const { data, error } = await supabase
  .storage
  .from('organization_files')
  .download(`org_123/${fileId}.pdf`);
```

### List Files

```http
GET /storage/v1/object/list/<bucket_name>
Authorization: Bearer <ANON_KEY>
apikey: <ANON_KEY>
```

**Parameters**:
- `prefix` - Filter by path prefix
- `limit` - Max number of files to return
- `offset` - Pagination offset
- `sortBy` - Sort by column (name, created_at, etc.)
- `order` - Sort direction (asc, desc)

---

## Authentication Integration

### Clerk + Supabase Flow

```
User → Clerk Auth → JWT Token → Supabase
                  ↓
          Clerk Webhook → selltonai-modal
                          ↓
              Sync to Supabase (users, organizations)
```

### JWT Validation

Supabase validates Clerk JWT tokens:

```javascript
// Client-side
const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  global: {
    headers: {
      Authorization: `Bearer ${clerkToken}`
    }
  }
});

// Server-side (selltonai-modal)
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY
);
```

### Token Claims

Clerk JWT tokens include:
```json
{
  "sub": "user_123",
  "org_id": "org_123",
  "org_name": "Acme Corp",
  "org_role": "admin",
  "email": "user@acme.com",
  "iat": 1234567890,
  "exp": 1234571490
}
```

---

## Rate Limits

### Supabase Rate Limits

| Endpoint | Rate Limit | Notes |
|----------|------------|-------|
| REST API | 50 requests/second per IP | Can be increased |
| Auth | 10 requests/second | Per project |
| Realtime | 100 connections | Per project |
| Storage | 500 requests/minute | Per project |

### Recommended Client-Side Limits

| Operation | Recommended Limit |
|-----------|-------------------|
| Campaign list | 1 request/second |
| Company search | 2 requests/second |
| Contact lookup | 3 requests/second |
| Bulk operations | 10 requests/minute |

### Backend Service Limits

Backend services (selltonai-modal, etc.) should:
- Use connection pooling
- Batch operations when possible
- Implement exponential backoff on rate limits
- Cache frequently accessed data

---

## Error Responses

### Standard Error Format

```json
{
  "code": "42501",
  "details": "new row violates row-level security policy for table \"campaigns\"",
  "hint": null,
  "message": "permission denied for table campaigns"
}
```

### Common Error Codes

| Code | Error | Description |
|------|-------|-------------|
| 42501 | RLS Violation | Query violates RLS policy |
| 400 | Bad Request | Invalid query syntax |
| 401 | Unauthorized | Invalid or missing API key |
| 403 | Forbidden | Insufficient permissions |
| 404 | Not Found | Table or resource not found |
| 408 | Request Timeout | Query took too long |
| 429 | Too Many Requests | Rate limit exceeded |
| 500 | Internal Server Error | Database error |
| 503 | Service Unavailable | Supabase down |

---

## Performance Contracts

### Query Performance SLOs

| Query Type | Target Latency | Max Latency |
|------------|----------------|-------------|
| Simple SELECT (indexed) | <50ms | <200ms |
| Complex SELECT (joins) | <100ms | <500ms |
| INSERT | <50ms | <200ms |
| UPDATE | <50ms | <200ms |
| DELETE | <50ms | <200ms |
| Full table scan | N/A | Avoid |

### Bulk Operation Contracts

| Operation | Max Items | Timeout | Notes |
|-----------|-----------|---------|-------|
| Bulk INSERT | 100 | 30s | Use `upsert` for duplicates |
| Bulk UPDATE | 100 | 30s | Filter carefully |
| Bulk DELETE | 50 | 30s | Use with caution |

---

## Database Operations Contracts

### Migration Contract

When a migration is deployed:

1. **Schema Changes**: Applied atomically
2. **Data Migrations**: Run in transactions when possible
3. **Index Creation**: Created after data is loaded
4. **RLS Policies**: Applied with schema changes
5. **Rollback**: Must be tested and documented

### Deployment Window

- **Production**: During low-traffic periods (maintenance windows)
- **Staging**: Any time (matches production schema)
- **Development**: Any time

### Rollback Procedure

1. Identify problematic migration
2. Revert migration file
3. Run `supabase migration down`
4. Verify schema integrity
5. Communicate to all services

---

## Cross-Service API Contracts

### Service Key Distribution

| Service | Key Type | Usage |
|---------|----------|-------|
| selltonai | Anon Key | Frontend queries (RLS enforced) |
| selltonai-modal | Service Role Key | Backend operations (RLS bypassed) |
| backoffice | Service Role Key | Admin operations (RLS bypassed) |
| selltonai-crawler | Service Role Key | Data enrichment (RLS bypassed) |
| selltonai-gmail-api | Service Role Key | Email operations (RLS bypassed) |
| selltonai-vector-api | Service Role Key | Vector processing (RLS bypassed) |
| sellton-onboard | Anon Key | Onboarding queries (RLS enforced) |

### Key Rotation

- **Anon Key**: Can be rotated without breaking changes
- **Service Role Key**: Rotation requires coordination with all services
- **JWT Secrets**: Managed by Clerk, rotated automatically

**Key Rotation Procedure**:
1. Generate new key in Supabase dashboard
2. Update key in all services
3. Verify all services work with new key
4. Remove old key

---

## Integration Examples

### TypeScript Client Setup

```typescript
// src/lib/supabase-client.ts
import { createClient } from '@supabase/supabase-js';

const supabaseUrl = process.env.SUPABASE_URL || '';
const supabaseAnonKey = process.env.SUPABASE_ANON_KEY || '';

export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  // Enable automatic RLS setting
  db: {
    schema: 'public',
  },
  // Set default headers
  headers: {
    'X-Client-Info': 'selltonai',
  },
});

// Set organization context
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

### Python Client Setup

```python
# supabase_client.py
from supabase import create_client, Client
import os

supabase_url = os.getenv('SUPABASE_URL')
supabase_key = os.getenv('SUPABASE_SERVICE_ROLE_KEY')

supabase: Client = create_client(supabase_url, supabase_key)

# Set organization context for RLS
def set_organization(org_id: str):
    result = supabase.rpc('set_current_org_id', {'org_id': org_id}).execute()
    if result.data:
        return result.data
    raise Exception(f"Failed to set org: {result.error}")
```

---

## Environment Variables

### Required Variables

```env
# All services
SUPABASE_URL=https://xxx.supabase.co
SUPABASE_ANON_KEY=eyJ...  # For frontend services
SUPABASE_SERVICE_ROLE_KEY=eyJ...  # For backend services
```

### Optional Variables

```env
# For local development
SUPABASE_LOCAL_URL=http://localhost:54321
SUPABASE_LOCAL_ANON_KEY=eyJ...
SUPABASE_LOCAL_SERVICE_KEY=eyJ...

# For debugging
SUPABASE_LOG_LEVEL=debug
SUPABASE_DB_LOG_LEVEL=debug
```

---

## Testing Contracts

### Test Environment

```bash
# Start local Supabase
supabase start

# Apply migrations
supabase db reset

# Generate TypeScript types
supabase gen types typescript --local > src/types/database.ts
```

### Test Data

```sql
-- Insert test organization
INSERT INTO organizations (id, name) VALUES ('test_org', 'Test Org');

-- Insert test user
INSERT INTO users (id, email, firstname, lastname) 
VALUES ('test_user', 'test@example.com', 'Test', 'User');

-- Link user to organization
INSERT INTO user_organizations (user_id, organization_id, role) 
VALUES ('test_user', 'test_org', 'admin');
```

---

## Summary

This document defines the API contracts for the Supabase database infrastructure. For complete database schema details, see:
- [Data Models](data-models.md)
- [Architecture](architecture.md)

For cross-service integration details, see:
- [Cross-Project Documentation](docs/cross-project/README.md)
