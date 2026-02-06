-- Add wizard_completed field to track if campaign creation wizard was fully completed
-- NOTE: This migration needs to be applied to production when ready.
-- Until then, the code checks metadata.completed_steps for backward compatibility.
ALTER TABLE campaigns
ADD COLUMN wizard_completed BOOLEAN DEFAULT FALSE;

-- Add comment explaining the field
COMMENT ON COLUMN campaigns.wizard_completed IS 'Indicates whether the campaign creation wizard was fully completed. Required to be true before campaign can be started.';

-- Update existing campaigns based on their status and metadata
-- Campaigns that are already active, paused, completed, or cancelled must have completed the wizard
UPDATE campaigns
SET wizard_completed = TRUE
WHERE status IN ('active', 'paused', 'completed', 'cancelled');

-- For draft campaigns, check if they have all required steps completed in metadata
UPDATE campaigns
SET wizard_completed = TRUE
WHERE status = 'draft'
  AND metadata->>'completed_steps' IS NOT NULL
  AND jsonb_array_length(metadata->'completed_steps') = 4
  AND metadata->'completed_steps' @> '["campaign-details", "lead-source", "curate-leads", "review-launch"]'::jsonb; 