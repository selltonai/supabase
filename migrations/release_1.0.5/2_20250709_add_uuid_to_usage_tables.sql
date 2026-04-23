-- Enable the pgcrypto extension if not already enabled
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- --- Migrate 'usage' table ---
-- The 'id' column already exists but has a numeric type. This script changes its type to UUID.

-- Step 1: Drop the existing primary key constraint.
ALTER TABLE usage DROP CONSTRAINT IF EXISTS usage_pkey;

-- Step 2: Alter the 'id' column type to UUID.
-- This assigns new random UUIDs to existing rows and sets a new default for future inserts.
ALTER TABLE usage ALTER COLUMN id DROP DEFAULT;
ALTER TABLE usage ALTER COLUMN id TYPE UUID USING (gen_random_uuid());
ALTER TABLE usage ALTER COLUMN id SET DEFAULT gen_random_uuid();

-- Step 3: Add the primary key constraint back on the new UUID 'id' column.
ALTER TABLE usage ADD PRIMARY KEY (id);

-- --- Migrate 'usage_summary' table (if it exists) ---
DO $$
BEGIN
    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'usage_summary') THEN
        IF EXISTS (
            SELECT 1 FROM information_schema.columns 
            WHERE table_name = 'usage_summary' AND column_name = 'id'
        ) THEN
            -- If 'id' column exists, migrate it to UUID.
            IF EXISTS (
                SELECT 1 FROM information_schema.table_constraints 
                WHERE table_name = 'usage_summary' AND constraint_type = 'PRIMARY KEY'
            ) THEN
                ALTER TABLE usage_summary DROP CONSTRAINT IF EXISTS usage_summary_pkey;
            END IF;

            ALTER TABLE usage_summary ALTER COLUMN id DROP DEFAULT;
            ALTER TABLE usage_summary ALTER COLUMN id TYPE UUID USING (gen_random_uuid());
            ALTER TABLE usage_summary ALTER COLUMN id SET DEFAULT gen_random_uuid();
            ALTER TABLE usage_summary ADD PRIMARY KEY (id);
        ELSE
            -- If 'id' column does not exist, add it as a UUID primary key.
            ALTER TABLE usage_summary ADD COLUMN id UUID PRIMARY KEY DEFAULT gen_random_uuid();
        END IF;
    END IF;
END $$; 