-- Migration: Fix UUID types in email_copy_tasks table
-- Date: 2025-01-31
-- Description: Fixes UUID type mismatches in email_copy_tasks table

-- First, check if the table exists and has the wrong column types
DO $$
BEGIN
    -- Check if contact_id is TEXT instead of UUID
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'email_copy_tasks' 
        AND column_name = 'contact_id' 
        AND data_type = 'text'
    ) THEN
        -- Convert contact_id from TEXT to UUID
        ALTER TABLE email_copy_tasks 
        ALTER COLUMN contact_id TYPE UUID USING contact_id::UUID;
        
        RAISE NOTICE 'Converted contact_id from TEXT to UUID';
    END IF;
    
    -- Check if company_id is TEXT instead of UUID
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'email_copy_tasks' 
        AND column_name = 'company_id' 
        AND data_type = 'text'
    ) THEN
        -- Convert company_id from TEXT to UUID
        ALTER TABLE email_copy_tasks 
        ALTER COLUMN company_id TYPE UUID USING company_id::UUID;
        
        RAISE NOTICE 'Converted company_id from TEXT to UUID';
    END IF;
    
    -- Check if campaign_id is TEXT instead of UUID
    IF EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'email_copy_tasks' 
        AND column_name = 'campaign_id' 
        AND data_type = 'text'
    ) THEN
        -- Convert campaign_id from TEXT to UUID
        ALTER TABLE email_copy_tasks 
        ALTER COLUMN campaign_id TYPE UUID USING campaign_id::UUID;
        
        RAISE NOTICE 'Converted campaign_id from TEXT to UUID';
    END IF;
    
END $$;

-- Add comments for the UUID columns
COMMENT ON COLUMN email_copy_tasks.contact_id IS 'Contact ID (UUID)';
COMMENT ON COLUMN email_copy_tasks.company_id IS 'Company ID (UUID)';
COMMENT ON COLUMN email_copy_tasks.campaign_id IS 'Campaign ID (UUID)'; 