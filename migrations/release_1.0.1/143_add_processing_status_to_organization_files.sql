-- Add processing_status column to organization_files table
-- This tracks the status of document processing: 'pending', 'processing', 'processed', 'error'
-- Migrates data from legacy 'status' column if it exists

ALTER TABLE organization_files 
ADD COLUMN IF NOT EXISTS processing_status TEXT DEFAULT 'pending' CHECK (processing_status IN ('pending', 'processing', 'processed', 'error'));

-- Create index for better query performance when filtering by status
CREATE INDEX IF NOT EXISTS idx_organization_files_processing_status ON organization_files(processing_status);

-- Migrate data from legacy 'status' column to 'processing_status' if 'status' column exists
DO $$
BEGIN
    -- Check if 'status' column exists and migrate data
    IF EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_name = 'organization_files' 
        AND column_name = 'status'
    ) THEN
        -- Map legacy status values to new processing_status values
        UPDATE organization_files 
        SET processing_status = CASE 
            WHEN status = 'uploaded' THEN 'pending'
            WHEN status = 'processing' THEN 'processing'
            WHEN status = 'processed' THEN 'processed'
            WHEN status = 'failed' THEN 'error'
            WHEN status = 'chunked' THEN 'processed'
            ELSE 'pending'
        END
        WHERE processing_status IS NULL OR processing_status = 'pending';
        
        RAISE NOTICE 'Migrated data from legacy status column to processing_status';
    ELSE
        -- If no legacy status column, set default for existing records
        UPDATE organization_files 
        SET processing_status = 'processed' 
        WHERE processing_status IS NULL OR processing_status = 'pending';
        
        RAISE NOTICE 'Set default processing_status for existing records';
    END IF;
END $$;

-- Add comment to the column
COMMENT ON COLUMN organization_files.processing_status IS 'Status of document processing: pending (not started), processing (in progress), processed (completed), error (failed)';

-- Optional: Drop legacy status column and its index after migration
-- Uncomment these lines if you want to remove the old column completely
-- DROP INDEX IF EXISTS idx_organization_files_status;
-- ALTER TABLE organization_files DROP COLUMN IF EXISTS status;

