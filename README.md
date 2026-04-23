# Database Migrations

This directory contains SQL migration files for the organization files and chunks functionality.

## Migration Order

Run the migrations in this order to properly set up the database:

1. **`3_20250108_organization_files_chunks_table.sql`** - Creates the main tables with proper vector dimensions
2. **`4_20250108_fix_vector_dimensions.sql`** - Fixes any existing tables with incorrect vector dimensions
3. **`20250108_vector_search_functions.sql`** - Creates vector search functions and indexes

## Fixing Vector Dimension Error

If you're getting the error `ERROR: 22023: column does not have dimensions`, it means your `chunk_embedding` column was created without specifying vector dimensions.

### Quick Fix

**Option 1: Use the complete migration (recommended)**
```sql
-- Run the complete migration that handles everything
\i run_migrations.sql
```

**Option 2: Run individual migrations in order**
```sql
-- 1. First, run the table creation migration
\i 3_20250108_organization_files_chunks_table.sql

-- 2. Fix any missing status column
\i 5_fix_missing_status_column.sql

-- 3. Then fix any dimension issues
\i 4_20250108_fix_vector_dimensions.sql

-- 4. Finally, add the search functions
\i 20250108_vector_search_functions.sql
```

### Manual Fix (if needed)

If the migrations don't work, you can manually fix the issue:

```sql
-- Check current column definition
\d organization_files_chunks

-- If chunk_embedding exists without dimensions, fix it:
ALTER TABLE organization_files_chunks 
ALTER COLUMN chunk_embedding TYPE vector(1536);

-- Or if that fails, recreate the column:
ALTER TABLE organization_files_chunks DROP COLUMN chunk_embedding;
ALTER TABLE organization_files_chunks ADD COLUMN chunk_embedding vector(1536);
```

## Vector Dimensions

The current setup uses **1536 dimensions** which is the standard for:
- OpenAI's `text-embedding-ada-002` model
- OpenAI's `text-embedding-3-large` model

If you're using a different embedding model, you may need to adjust the dimension:

- **OpenAI text-embedding-3-large**: 3072 dimensions
- **Sentence Transformers (many models)**: 384, 512, or 768 dimensions
- **Cohere embed models**: 1024 or 4096 dimensions

To change dimensions, update the migration files and replace `vector(1536)` with your desired dimension count.

## Testing the Setup

After running the migrations, you can test the setup:

```sql
-- Test inserting a chunk with embedding
INSERT INTO organization_files_chunks (
    organization_id, 
    chunk_text, 
    chunk_embedding
) VALUES (
    'test_org',
    'This is a test chunk',
    ARRAY[0.1, 0.2, 0.3, ...]::vector(1536)  -- 1536 values
);

-- Test vector similarity search
SELECT * FROM match_chunks(
    ARRAY[0.1, 0.2, 0.3, ...]::vector(1536),  -- query embedding
    'test_org',  -- organization_id
    0.7,         -- similarity threshold
    5            -- max results
);
```

## Services Usage

Once the database is set up, you can use the Python services:

```python
from sellton_api.core.database import (
    ConnectionManager,
    OrganizationFilesService,
    OrganizationFilesChunksService
)

# Initialize services
connection_manager = ConnectionManager()
files_service = OrganizationFilesService(connection_manager)
chunks_service = OrganizationFilesChunksService(connection_manager)

# Create a file and chunks
file_data = files_service.create_file(
    organization_id="org_123",
    file_name="document.pdf"
)

chunk_data = chunks_service.create_chunk(
    organization_id="org_123",
    chunk_text="Document content...",
    chunk_embedding=[0.1] * 1536,  # Your actual embedding
    file_id=file_data['id']
)
```

## Troubleshooting

### Common Issues

1. **"column does not have dimensions"**: Run migration #4 to fix vector dimensions
2. **"column status does not exist"**: Run migration #5 to add missing status column
3. **"function match_chunks does not exist"**: Run the vector search functions migration
4. **"extension vector does not exist"**: Install pgvector extension first
5. **Performance issues**: Ensure vector indexes are created (HNSW or IVFFlat)

### Performance Notes

- **HNSW indexes**: Better for query performance, more memory usage
- **IVFFlat indexes**: Better for memory usage, slightly slower queries
- The migrations will prefer HNSW if available, fall back to IVFFlat

### Monitoring

Check your setup:

```sql
-- Check table structure
\d organization_files_chunks

-- Check indexes
\di+ *chunks*

-- Check functions
\df match_chunks
\df hybrid_search_chunks
\df find_similar_chunks
```

## Additional Migrations

### Campaigns Table (3_20250102_campaigns_table.sql)
- Creates `campaigns` table for storing campaign data
- Supports JSON fields for flexible data storage (pain_points, keywords, etc.)
- Includes organization_id foreign key constraint
- Provides indexes for performance
- Enables Row Level Security (RLS)

Example usage:
```sql
-- Insert a new campaign
INSERT INTO campaigns (organization_id, name, description, industry, company_size, location, pain_points, keywords)
VALUES (
    'org_123', 
    'SaaS Growth Campaign', 
    'Find companies that need our SaaS solution',
    'Software Development',
    '50-500 employees',
    'United States, Europe',
    '["Manual processes", "Scalability issues", "Integration challenges"]'::jsonb,
    '["SaaS", "software", "automation", "integration", "API"]'::jsonb
);
```
``` 