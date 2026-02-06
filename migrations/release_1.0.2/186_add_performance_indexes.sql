-- Migration: 186_add_performance_indexes.sql
-- Description: Add indexes to reduce Disk I/O by preventing sequential table scans
-- Issue: Supabase warning about Disk I/O budget exhaustion
-- 
-- Analysis of pg_stat_user_tables showed these tables have high sequential scans:
-- - organization_settings: 100 seq_scans, 0 idx_scans (CRITICAL)
-- - interviewer: 89 seq_scans, 0 idx_scans
-- - organization: 79 seq_scans, 0 idx_scans  
-- - campaign_seed_companies: 40 seq_scans, 0 idx_scans
-- - tasks: 17 seq_scans (some indexes exist but need optimization)
-- - campaign_companies: 10 seq_scans (needs composite index)

-- ============================================================================
-- COMPANIES TABLE INDEXES
-- ============================================================================
-- Used heavily by cron jobs: find_by(organization_id, processing_status)
CREATE INDEX IF NOT EXISTS idx_companies_org_status 
ON companies(organization_id, processing_status);

-- Index for looking up companies by LinkedIn URL (frequently used in enrichment)
CREATE INDEX IF NOT EXISTS idx_companies_linkedin_url 
ON companies(linkedin_url) 
WHERE linkedin_url IS NOT NULL;

-- ============================================================================
-- TASKS TABLE INDEXES
-- ============================================================================
-- Used for finding tasks by organization and status
CREATE INDEX IF NOT EXISTS idx_tasks_org_status 
ON tasks(organization_id, status);

-- Used for finding tasks by campaign
CREATE INDEX IF NOT EXISTS idx_tasks_campaign_id 
ON tasks(campaign_id);

-- Used for finding tasks by contact
CREATE INDEX IF NOT EXISTS idx_tasks_contact_id 
ON tasks(contact_id);

-- Composite index for common query pattern: open tasks by org
CREATE INDEX IF NOT EXISTS idx_tasks_org_status_created 
ON tasks(organization_id, status, created_at DESC);

-- ============================================================================
-- USAGE TABLE INDEXES
-- ============================================================================
-- Used for usage analytics and billing queries
CREATE INDEX IF NOT EXISTS idx_usage_org_created 
ON usage(organization_id, created_at DESC);

-- Used for filtering by campaign
CREATE INDEX IF NOT EXISTS idx_usage_campaign_id 
ON usage(campaign_id) 
WHERE campaign_id IS NOT NULL;

-- ============================================================================
-- ORGANIZATION_SETTINGS TABLE INDEXES (100 seq_scans, 0 idx_scans - CRITICAL)
-- ============================================================================
-- Primary lookup is by organization_id
CREATE INDEX IF NOT EXISTS idx_organization_settings_org_id 
ON organization_settings(organization_id);

-- ============================================================================
-- ORGANIZATION TABLE INDEXES (79 seq_scans, 0 idx_scans)
-- ============================================================================
-- Already has primary key, but add index for deleted filter
CREATE INDEX IF NOT EXISTS idx_organization_deleted 
ON organization(deleted) 
WHERE deleted = false;

-- ============================================================================
-- INTERVIEWER TABLE INDEXES (89 seq_scans, 0 idx_scans)
-- ============================================================================
-- Primary lookup pattern
CREATE INDEX IF NOT EXISTS idx_interviewer_org_id 
ON interviewer(organization_id);

-- ============================================================================
-- CAMPAIGN_SEED_COMPANIES TABLE INDEXES (40 seq_scans, 0 idx_scans)
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_campaign_seed_companies_campaign_id 
ON campaign_seed_companies(campaign_id);

CREATE INDEX IF NOT EXISTS idx_campaign_seed_companies_org_id 
ON campaign_seed_companies(organization_id);

-- ============================================================================
-- CAMPAIGN_COMPANIES TABLE INDEXES (10 seq_scans, high tuple reads)
-- ============================================================================
-- Composite index for the most common lookup pattern
CREATE INDEX IF NOT EXISTS idx_campaign_companies_org_campaign 
ON campaign_companies(organization_id, campaign_id);

-- Index for finding companies by campaign
CREATE INDEX IF NOT EXISTS idx_campaign_companies_campaign_id 
ON campaign_companies(campaign_id);

-- ============================================================================
-- COMPANY_CONTACTS TABLE INDEXES (frequently joined)
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_company_contacts_company_id 
ON company_contacts(company_id);

CREATE INDEX IF NOT EXISTS idx_company_contacts_contact_id 
ON company_contacts(contact_id);

-- ============================================================================
-- CONTACTS TABLE INDEXES (for contact lookups)
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_contacts_org_id 
ON contacts(organization_id);

CREATE INDEX IF NOT EXISTS idx_contacts_email 
ON contacts(email) 
WHERE email IS NOT NULL;

-- ============================================================================
-- CAMPAIGNS TABLE INDEXES
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_campaigns_org_status 
ON campaigns(organization_id, status);

-- ============================================================================
-- ORGANIZATION_FILES TABLE INDEXES (4 seq_scans)
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_organization_files_org_id 
ON organization_files(organization_id);

-- ============================================================================
-- Analyze tables to update statistics after creating indexes
-- ============================================================================
ANALYZE companies;
ANALYZE tasks;
ANALYZE usage;
ANALYZE organization_settings;
ANALYZE organization;
ANALYZE interviewer;
ANALYZE campaign_seed_companies;
ANALYZE campaign_companies;
ANALYZE company_contacts;
ANALYZE contacts;
ANALYZE campaigns;
ANALYZE organization_files;

-- ============================================================================
-- COMMENTS
-- ============================================================================
COMMENT ON INDEX idx_companies_org_status IS 'Optimizes cron job queries filtering by organization and processing status';
COMMENT ON INDEX idx_tasks_org_status IS 'Optimizes task queries filtering by organization and status';
COMMENT ON INDEX idx_usage_org_created IS 'Optimizes usage analytics queries by organization and date';
COMMENT ON INDEX idx_organization_settings_org_id IS 'Fixes 100+ sequential scans on organization_settings table';

