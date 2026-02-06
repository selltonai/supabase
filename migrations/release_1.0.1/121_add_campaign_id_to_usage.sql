-- Migration: Add campaign_id to usage table for campaign-level tracking
-- Date: 2025-01-31
-- Description: Adds campaign_id column to track usage per campaign, enabling better cost attribution and reporting

-- Add campaign_id column to usage table
ALTER TABLE usage ADD COLUMN IF NOT EXISTS campaign_id TEXT;

-- Add index for efficient campaign-based queries
CREATE INDEX IF NOT EXISTS idx_usage_campaign_id ON usage(campaign_id);

-- Add composite index for common query patterns (organization + campaign)
CREATE INDEX IF NOT EXISTS idx_usage_org_campaign ON usage(organization_id, campaign_id) WHERE campaign_id IS NOT NULL;

-- Add comment for documentation
COMMENT ON COLUMN usage.campaign_id IS 'Campaign ID for tracking usage per campaign (nullable - not all usage is campaign-related)';

-- Update usage_summary view to potentially support campaign-level aggregation in the future
-- (Currently keeping it as-is, but the structure supports future expansion)

