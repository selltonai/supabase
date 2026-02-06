-- Remove company_id column from contacts table
-- This column should not exist as we use the company_contacts junction table instead

BEGIN;

-- Check if the column exists before trying to drop it
DO $$ 
BEGIN
    IF EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_name = 'contacts' 
        AND column_name = 'company_id'
    ) THEN
        -- Drop the column if it exists
        ALTER TABLE contacts DROP COLUMN company_id;
        RAISE NOTICE 'Dropped company_id column from contacts table';
    ELSE
        RAISE NOTICE 'company_id column does not exist in contacts table';
    END IF;
END $$;

COMMIT;

-- Add comment
COMMENT ON TABLE contacts IS 'Contacts table - company relationships are managed via company_contacts junction table';