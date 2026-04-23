-- Migration: Add crm_list_id to campaigns table to track CRM list source
-- Description: Track which CRM list was used to create a campaign (for csv, lookalike, or manual sources)
-- Author: System
-- Date: 2026-04-15

-- Add crm_list_id column to campaigns table
ALTER TABLE campaigns 
ADD COLUMN crm_list_id TEXT;

-- Add index for performance on CRM list filtering
CREATE INDEX idx_campaigns_crm_list_id ON campaigns(crm_list_id) WHERE crm_list_id IS NOT NULL;

-- Add foreign key constraint (optional - companies.crm_list_id is informal reference)
-- Note: Not adding FK to avoid circular dependency issues during migration

-- Add comment explaining the new field
COMMENT ON COLUMN campaigns.crm_list_id IS 'ID of the CRM list used to create this campaign (if lead_source is crm_list). NULL for csv/lookalike/manual campaigns.';

-- Migration: 233_add_imported_status.sql MUST be applied before this migration
-- That migration adds 'imported' to the companies.processing_status constraint