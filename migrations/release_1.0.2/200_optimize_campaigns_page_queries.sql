-- Migration: Optimize Campaigns Page Queries
-- Description: Adds indexes to speed up campaigns page loading
-- Date: 2025-01-XX
-- Author: System

-- ============================================================================
-- TASKS TABLE INDEXES (for pending verification task lookups)
-- ============================================================================
-- Composite index for finding pending verification tasks by campaign
CREATE INDEX IF NOT EXISTS idx_tasks_campaign_verification 
ON tasks(organization_id, task_type, status, campaign_id)
WHERE task_type = 'company_verification' AND status = 'pending';

-- Index for tasks without campaign_id (null campaign_id lookups)
CREATE INDEX IF NOT EXISTS idx_tasks_verification_no_campaign 
ON tasks(organization_id, task_type, status, company_id)
WHERE task_type = 'company_verification' AND status = 'pending' AND campaign_id IS NULL;

-- ============================================================================
-- COMPANIES TABLE INDEXES (for processing_status filtering)
-- ============================================================================
-- Index for filtering by processing_status (used in campaign company counts)
CREATE INDEX IF NOT EXISTS idx_companies_processing_status 
ON companies(processing_status)
WHERE processing_status IS NOT NULL;

-- Composite index for blocked_by_icp filtering
CREATE INDEX IF NOT EXISTS idx_companies_blocked_icp 
ON companies(blocked_by_icp)
WHERE blocked_by_icp = true;

-- ============================================================================
-- CAMPAIGN_COMPANIES TABLE INDEXES (optimize joins with companies)
-- ============================================================================
-- Composite index for the optimized batch query pattern
-- This helps with: SELECT campaign_id, company FROM campaign_companies WHERE campaign_id IN (...) AND organization_id = ...
CREATE INDEX IF NOT EXISTS idx_campaign_companies_batch_lookup 
ON campaign_companies(organization_id, campaign_id, company_id);

-- ============================================================================
-- CAMPAIGN_EMAILS TABLE INDEXES (for email metrics)
-- ============================================================================
-- Index for counting opened emails
CREATE INDEX IF NOT EXISTS idx_campaign_emails_opened 
ON campaign_emails(campaign_id, opened_at)
WHERE opened_at IS NOT NULL;

-- Index for counting replied emails
CREATE INDEX IF NOT EXISTS idx_campaign_emails_replied 
ON campaign_emails(campaign_id, replied_at)
WHERE replied_at IS NOT NULL;

-- ============================================================================
-- CAMPAIGN_ACTIVITIES TABLE INDEXES (for activity metrics)
-- ============================================================================
-- Index for counting meeting bookings
CREATE INDEX IF NOT EXISTS idx_campaign_activities_meetings 
ON campaign_activities(campaign_id, activity_type)
WHERE activity_type = 'meeting_booked';

-- ============================================================================
-- Analyze tables to update query planner statistics
-- ============================================================================
ANALYZE tasks;
ANALYZE companies;
ANALYZE campaign_companies;
ANALYZE campaign_emails;
ANALYZE campaign_activities;

