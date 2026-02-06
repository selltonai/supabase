-- Migration: Add metadata column to campaigns table
-- Description: Adds the metadata JSONB column back to campaigns table
-- Author: System
-- Date: 2025-02-06

-- Add metadata column to campaigns table if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'campaigns' 
        AND column_name = 'metadata'
    ) THEN
        ALTER TABLE campaigns ADD COLUMN metadata JSONB DEFAULT '{}';
    END IF;
END $$;

-- Add comment for documentation
COMMENT ON COLUMN campaigns.metadata IS 'Additional metadata for campaigns including external leads, workflow stage, and other campaign-specific data'; 