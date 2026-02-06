-- Migration: Add Campaign Workflow Fields
-- Description: Adds workflow JSON storage and current node tracking to campaigns table
-- Author: System
-- Date: 2025-01-XX

-- Add workflow fields to campaigns table
ALTER TABLE campaigns 
ADD COLUMN IF NOT EXISTS workflow JSONB DEFAULT NULL,
ADD COLUMN IF NOT EXISTS current_workflow_node_id UUID DEFAULT NULL;

-- Add comment for documentation
COMMENT ON COLUMN campaigns.workflow IS 'JSON structure containing the workflow steps (Email → Wait pattern) with UUIDs for each node';
COMMENT ON COLUMN campaigns.current_workflow_node_id IS 'UUID of the current workflow node being executed for this campaign';

-- Create index for current_workflow_node_id lookups
CREATE INDEX IF NOT EXISTS idx_campaigns_current_workflow_node_id ON campaigns(current_workflow_node_id) WHERE current_workflow_node_id IS NOT NULL;




