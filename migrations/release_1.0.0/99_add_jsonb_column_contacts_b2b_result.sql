-- Migration: Add Email Validation Response to Contacts Table
-- Description: Adds email_validation_response field to store email validation API responses
-- Author: System
-- Date: 2025-01-16

-- Add email_validation_response column to contacts table
ALTER TABLE contacts 
  ADD COLUMN IF NOT EXISTS email_validation_response JSONB DEFAULT NULL;

-- Create index for performance when querying email validation data
CREATE INDEX IF NOT EXISTS idx_contacts_email_validation_response ON contacts USING GIN(email_validation_response);

-- Add comment for documentation
COMMENT ON COLUMN contacts.email_validation_response IS 'Email validation response from email management API including mx record, domain type, status, and validation details';

-- Example of the JSON structure that will be stored:
-- {
--   "refId": "9e367d56-2990-48a9-bb3d-041685b35982",
--   "state": "DONE",
--   "input": {
--     "firstname": "Axel",
--     "lastname": "Gerleman", 
--     "domain": "profil.com"
--   },
--   "output": [{
--     "mx": {
--       "record": "mail.profil-research.de",
--       "google": false,
--       "found": true,
--       "provider": "other"
--     },
--     "domainType": "CATCH_ALL",
--     "status": "INVALID",
--     "subStatus": "EMPTY",
--     "date": "2025-07-16T12:14:15.000000",
--     "free": false,
--     "generic": false,
--     "found": false
--   }]
-- } 