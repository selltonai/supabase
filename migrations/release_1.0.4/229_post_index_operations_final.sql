-- Migration: Final Post-Index Operations
-- Description: Operations that must run after concurrent index creation
-- Author: System
-- Date: 2026-03-27
-- Compatible with Supabase PostgreSQL

-- Add comments for indexes that exist
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_companies_org_status') THEN
        EXECUTE 'COMMENT ON INDEX idx_companies_org_status IS ''Index for company status queries by organization''';
    END IF;
    
    IF EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_companies_org_processing') THEN
        EXECUTE 'COMMENT ON INDEX idx_companies_org_processing IS ''Index for company processing status with ICP blocking''';
    END IF;
    
    IF EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_tasks_org_status') THEN
        EXECUTE 'COMMENT ON INDEX idx_tasks_org_status IS ''Index for task status queries by organization''';
    END IF;
    
    IF EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_tasks_org_type_status') THEN
        EXECUTE 'COMMENT ON INDEX idx_tasks_org_type_status IS ''Index for task type and status queries by organization''';
    END IF;
    
    IF EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_tasks_dashboard_stats') THEN
        EXECUTE 'COMMENT ON INDEX idx_tasks_dashboard_stats IS ''Optimized index for dashboard stats queries''';
    END IF;
    
    IF EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_campaign_companies_org_campaign') THEN
        EXECUTE 'COMMENT ON INDEX idx_campaign_companies_org_campaign IS ''Index for campaign company queries by organization''';
    END IF;
    
    IF EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_campaign_companies_campaign_company') THEN
        EXECUTE 'COMMENT ON INDEX idx_campaign_companies_campaign_company IS ''Index for campaign-company relationship queries''';
    END IF;
    
    IF EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_campaign_companies_count') THEN
        EXECUTE 'COMMENT ON INDEX idx_campaign_companies_count IS ''Index for campaign company count queries''';
    END IF;
    
    IF EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_contacts_org_status') THEN
        EXECUTE 'COMMENT ON INDEX idx_contacts_org_status IS ''Index for contact status queries by organization''';
    END IF;
END $$;

-- Analyze tables to update statistics after index creation
ANALYZE companies;
ANALYZE tasks;
ANALYZE campaign_companies;
ANALYZE contacts;

-- Verify indexes were created
SELECT 
    indexname,
    tablename,
    'EXISTS' as status
FROM pg_indexes 
WHERE tablename IN ('companies', 'tasks', 'campaign_companies', 'contacts')
AND indexname LIKE 'idx_%'
ORDER BY tablename, indexname;
