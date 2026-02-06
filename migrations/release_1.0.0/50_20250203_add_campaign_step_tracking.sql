-- Migration: Add Campaign Step Tracking and Enhanced Form Data
-- Description: Adds current_step field and enhances metadata for better form state persistence
-- Author: System
-- Date: 2025-02-03

-- Add current_step field to campaigns table
ALTER TABLE campaigns ADD COLUMN IF NOT EXISTS current_step INTEGER DEFAULT 0;
ALTER TABLE campaigns ADD COLUMN IF NOT EXISTS completed_steps TEXT[] DEFAULT '{}';

-- Add index for performance
CREATE INDEX IF NOT EXISTS idx_campaigns_current_step ON campaigns(current_step);

-- Update metadata to store more detailed form state
COMMENT ON COLUMN campaigns.current_step IS 'Current step index in the campaign creation wizard (0-3)';
COMMENT ON COLUMN campaigns.completed_steps IS 'Array of completed step IDs for tracking progress';
COMMENT ON COLUMN campaigns.metadata IS 'Enhanced to store: lead_source, selected_leads, csv_data, csv_file_name, form_state, etc.';

-- Create function to update campaign step progress
CREATE OR REPLACE FUNCTION update_campaign_step(
    campaign_id UUID,
    step_index INTEGER,
    completed_step_ids TEXT[]
)
RETURNS void AS $$
BEGIN
    UPDATE campaigns 
    SET 
        current_step = step_index,
        completed_steps = completed_step_ids,
        updated_at = NOW()
    WHERE id = campaign_id;
END;
$$ LANGUAGE plpgsql;

-- Add comment for the new function
COMMENT ON FUNCTION update_campaign_step IS 'Updates campaign step progress and completed steps array'; 