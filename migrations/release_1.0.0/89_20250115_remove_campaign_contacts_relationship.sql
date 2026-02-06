-- Migration: Remove Campaign Contacts Relationship Table
-- Description: Removes the campaign_contacts table and related functions since we're replacing it with campaign_companies
-- Author: System
-- Date: 2025-01-15

-- IMPORTANT: This migration removes the campaign_contacts table and replaces it with campaign_companies
-- The API routes in src/app/api/campaigns/ need to be updated to use campaign_companies instead

-- First, check if the table exists before attempting to drop things
DO $$ 
BEGIN
    -- Drop the triggers if they exist
    IF EXISTS (SELECT 1 FROM information_schema.triggers WHERE trigger_name = 'update_campaign_contacts_updated_at') THEN
        DROP TRIGGER update_campaign_contacts_updated_at ON campaign_contacts;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.triggers WHERE trigger_name = 'trigger_update_campaign_total_contacts') THEN
        DROP TRIGGER trigger_update_campaign_total_contacts ON campaign_contacts;
    END IF;
    
    -- Drop the function if it exists
    IF EXISTS (SELECT 1 FROM information_schema.routines WHERE routine_name = 'update_campaign_total_contacts') THEN
        DROP FUNCTION update_campaign_total_contacts();
    END IF;
    
    -- Drop the RLS policies if the table exists
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'campaign_contacts') THEN
        DROP POLICY IF EXISTS "Users can view campaign contacts in their organization" ON campaign_contacts;
        DROP POLICY IF EXISTS "Users can create campaign contacts in their organization" ON campaign_contacts;
        DROP POLICY IF EXISTS "Users can update campaign contacts in their organization" ON campaign_contacts;
        DROP POLICY IF EXISTS "Users can delete campaign contacts in their organization" ON campaign_contacts;
        DROP POLICY IF EXISTS "Users can manage campaign contacts in their organization" ON campaign_contacts;
        
        -- Drop the table (this will also drop all indexes and constraints)
        DROP TABLE campaign_contacts CASCADE;
    END IF;
END $$;

-- Update the campaigns table comment to reflect the change
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'campaigns') THEN
        COMMENT ON TABLE campaigns IS 'Campaign management table - removed campaign_contacts relationship in favor of campaign_companies relationship (migration 89_20250115)';
    END IF;
END $$; 