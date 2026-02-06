-- Migration: Add Outreach Strategy to Companies Table
-- Description: Adds outreach_strategy field to store outreach strategy data as JSONB
-- Author: System
-- Date: 2025-08-20

-- Add outreach_strategy column to companies table
ALTER TABLE companies 
  ADD COLUMN IF NOT EXISTS outreach_strategy JSONB DEFAULT NULL;

-- Create index for performance when querying outreach strategy data
CREATE INDEX IF NOT EXISTS idx_companies_outreach_strategy ON companies USING GIN(outreach_strategy);

-- Add comment for documentation
COMMENT ON COLUMN companies.outreach_strategy IS 'Outreach strategy configuration and data stored as JSONB including approach methods, messaging preferences, and timing settings';

-- Example of the JSON structure that will be stored:
-- {
--   "approach": "personalized_email",
--   "messaging_tone": "professional", 
--   "follow_up_sequence": [
--     {
--       "step": 1,
--       "delay_days": 3,
--       "message_type": "email",
--       "template_id": "follow_up_1"
--     }
--   ],
--   "preferred_channels": ["email", "linkedin"],
--   "timing_preferences": {
--     "best_days": ["tuesday", "wednesday", "thursday"],
--     "best_hours": [9, 10, 11, 14, 15]
--   },
--   "custom_fields": {},
--   "created_at": "2025-08-20T10:00:00Z",
--   "updated_at": "2025-08-20T10:00:00Z"
-- }