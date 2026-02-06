-- Migration: Remove selected_contacts column from campaigns table
-- Description: Removes the deprecated selected_contacts column as contacts are now managed via campaign_contacts relationship table
-- Author: System
-- Date: 2025-01-30

-- Drop the selected_contacts column from campaigns table
ALTER TABLE campaigns DROP COLUMN IF EXISTS selected_contacts;

-- Add comment explaining the change
COMMENT ON TABLE campaigns IS 'Stores email marketing campaigns and their performance metrics. Contacts are managed via campaign_contacts relationship table.'; 