-- Migration: Update Contacts Table for API Response Structure
-- Description: Adds all necessary fields to contacts table to match the API response structure
-- Author: System
-- Date: 2025-01-15

-- Add all new fields from the API response to contacts table
ALTER TABLE contacts 
  -- LinkedIn profile information
  ADD COLUMN IF NOT EXISTS linkedin_url TEXT,
  ADD COLUMN IF NOT EXISTS linkedin_identifier TEXT,
  ADD COLUMN IF NOT EXISTS linkedin_entity_urn TEXT,
  ADD COLUMN IF NOT EXISTS linkedin_object_urn TEXT,
  ADD COLUMN IF NOT EXISTS firstname TEXT,
  ADD COLUMN IF NOT EXISTS lastname TEXT,
  ADD COLUMN IF NOT EXISTS birth_date DATE,
  ADD COLUMN IF NOT EXISTS headline TEXT,
  ADD COLUMN IF NOT EXISTS profile_picture TEXT,
  ADD COLUMN IF NOT EXISTS background_image TEXT,
  ADD COLUMN IF NOT EXISTS is_open_to_work BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS summary TEXT,
  ADD COLUMN IF NOT EXISTS is_influencer BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS is_premium BOOLEAN DEFAULT FALSE,
  
  -- Location information (enhanced)
  ADD COLUMN IF NOT EXISTS location JSONB, -- Full location object
  
  -- Professional information
  ADD COLUMN IF NOT EXISTS current_company_name TEXT,
  ADD COLUMN IF NOT EXISTS current_company_id TEXT,
  ADD COLUMN IF NOT EXISTS current_company_logo TEXT,
  ADD COLUMN IF NOT EXISTS current_company_url TEXT,
  ADD COLUMN IF NOT EXISTS current_position_title TEXT,
  ADD COLUMN IF NOT EXISTS current_position_start_date TIMESTAMPTZ,
  
  -- Education, skills, and experience (JSONB arrays)
  ADD COLUMN IF NOT EXISTS organizations JSONB, -- Array of organizations
  ADD COLUMN IF NOT EXISTS educations JSONB, -- Array of education records
  ADD COLUMN IF NOT EXISTS patents JSONB, -- Array of patents
  ADD COLUMN IF NOT EXISTS awards JSONB, -- Array of awards
  ADD COLUMN IF NOT EXISTS certifications JSONB, -- Array of certifications
  ADD COLUMN IF NOT EXISTS projects JSONB, -- Array of projects
  ADD COLUMN IF NOT EXISTS publications JSONB, -- Array of publications
  ADD COLUMN IF NOT EXISTS courses JSONB, -- Array of courses
  ADD COLUMN IF NOT EXISTS test_scores JSONB, -- Array of test scores
  ADD COLUMN IF NOT EXISTS position_groups JSONB, -- Array of position groups (work history)
  ADD COLUMN IF NOT EXISTS volunteer_experiences JSONB, -- Array of volunteer experiences
  ADD COLUMN IF NOT EXISTS languages JSONB, -- Array of languages
  ADD COLUMN IF NOT EXISTS skills JSONB, -- Array of skills
  ADD COLUMN IF NOT EXISTS recommendations JSONB, -- Array of recommendations
  ADD COLUMN IF NOT EXISTS network_info JSONB, -- Network information
  
  -- Analysis data (complete analysis object)
  ADD COLUMN IF NOT EXISTS analysis JSONB, -- Complete analysis including model, source, score, selling, hiring, assessments
  
  -- Activities data (social media activities)
  ADD COLUMN IF NOT EXISTS activities JSONB, -- Complete activities object including content posts and pagination
  
  -- Contact metadata
  ADD COLUMN IF NOT EXISTS contact_id_from_api TEXT, -- Contact ID from the API response
  ADD COLUMN IF NOT EXISTS company_id_from_api TEXT, -- Company ID from the API response
  ADD COLUMN IF NOT EXISTS source TEXT DEFAULT 'campaign_processing',
  ADD COLUMN IF NOT EXISTS extraction_timestamp TIMESTAMPTZ;

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_contacts_linkedin_url ON contacts(linkedin_url);
CREATE INDEX IF NOT EXISTS idx_contacts_linkedin_identifier ON contacts(linkedin_identifier);
CREATE INDEX IF NOT EXISTS idx_contacts_linkedin_entity_urn ON contacts(linkedin_entity_urn);
CREATE INDEX IF NOT EXISTS idx_contacts_linkedin_object_urn ON contacts(linkedin_object_urn);
CREATE INDEX IF NOT EXISTS idx_contacts_firstname ON contacts(firstname);
CREATE INDEX IF NOT EXISTS idx_contacts_lastname ON contacts(lastname);
CREATE INDEX IF NOT EXISTS idx_contacts_headline ON contacts(headline);
CREATE INDEX IF NOT EXISTS idx_contacts_current_company_name ON contacts(current_company_name);
CREATE INDEX IF NOT EXISTS idx_contacts_current_company_id ON contacts(current_company_id);
CREATE INDEX IF NOT EXISTS idx_contacts_current_position_title ON contacts(current_position_title);
CREATE INDEX IF NOT EXISTS idx_contacts_contact_id_from_api ON contacts(contact_id_from_api);
CREATE INDEX IF NOT EXISTS idx_contacts_company_id_from_api ON contacts(company_id_from_api);
CREATE INDEX IF NOT EXISTS idx_contacts_extraction_timestamp ON contacts(extraction_timestamp);

-- Create GIN indexes for JSONB columns
CREATE INDEX IF NOT EXISTS idx_contacts_location_gin ON contacts USING GIN (location);
CREATE INDEX IF NOT EXISTS idx_contacts_organizations_gin ON contacts USING GIN (organizations);
CREATE INDEX IF NOT EXISTS idx_contacts_educations_gin ON contacts USING GIN (educations);
CREATE INDEX IF NOT EXISTS idx_contacts_position_groups_gin ON contacts USING GIN (position_groups);
CREATE INDEX IF NOT EXISTS idx_contacts_skills_gin ON contacts USING GIN (skills);
CREATE INDEX IF NOT EXISTS idx_contacts_analysis_gin ON contacts USING GIN (analysis);
CREATE INDEX IF NOT EXISTS idx_contacts_activities_gin ON contacts USING GIN (activities);
CREATE INDEX IF NOT EXISTS idx_contacts_certifications_gin ON contacts USING GIN (certifications);
CREATE INDEX IF NOT EXISTS idx_contacts_languages_gin ON contacts USING GIN (languages);

-- Add comments for documentation
COMMENT ON COLUMN contacts.linkedin_url IS 'LinkedIn profile URL';
COMMENT ON COLUMN contacts.linkedin_identifier IS 'LinkedIn profile identifier/slug';
COMMENT ON COLUMN contacts.linkedin_entity_urn IS 'LinkedIn entity URN identifier';
COMMENT ON COLUMN contacts.linkedin_object_urn IS 'LinkedIn object URN identifier';
COMMENT ON COLUMN contacts.firstname IS 'First name from LinkedIn profile';
COMMENT ON COLUMN contacts.lastname IS 'Last name from LinkedIn profile';
COMMENT ON COLUMN contacts.birth_date IS 'Birth date from LinkedIn profile';
COMMENT ON COLUMN contacts.headline IS 'Professional headline from LinkedIn profile';
COMMENT ON COLUMN contacts.profile_picture IS 'URL to LinkedIn profile picture';
COMMENT ON COLUMN contacts.background_image IS 'URL to LinkedIn background image';
COMMENT ON COLUMN contacts.is_open_to_work IS 'Whether the contact is open to work opportunities';
COMMENT ON COLUMN contacts.summary IS 'Professional summary from LinkedIn profile';
COMMENT ON COLUMN contacts.is_influencer IS 'Whether the contact is a LinkedIn influencer';
COMMENT ON COLUMN contacts.is_premium IS 'Whether the contact has LinkedIn Premium';
COMMENT ON COLUMN contacts.location IS 'JSONB object containing location information (country, city, state, etc.)';
COMMENT ON COLUMN contacts.current_company_name IS 'Name of current company';
COMMENT ON COLUMN contacts.current_company_id IS 'ID of current company';
COMMENT ON COLUMN contacts.current_company_logo IS 'URL to current company logo';
COMMENT ON COLUMN contacts.current_company_url IS 'URL to current company LinkedIn page';
COMMENT ON COLUMN contacts.current_position_title IS 'Current job title';
COMMENT ON COLUMN contacts.current_position_start_date IS 'Start date of current position';
COMMENT ON COLUMN contacts.organizations IS 'JSONB array of organizations the contact is associated with';
COMMENT ON COLUMN contacts.educations IS 'JSONB array of education records';
COMMENT ON COLUMN contacts.patents IS 'JSONB array of patents';
COMMENT ON COLUMN contacts.awards IS 'JSONB array of awards';
COMMENT ON COLUMN contacts.certifications IS 'JSONB array of certifications';
COMMENT ON COLUMN contacts.projects IS 'JSONB array of projects';
COMMENT ON COLUMN contacts.publications IS 'JSONB array of publications';
COMMENT ON COLUMN contacts.courses IS 'JSONB array of courses';
COMMENT ON COLUMN contacts.test_scores IS 'JSONB array of test scores';
COMMENT ON COLUMN contacts.position_groups IS 'JSONB array of position groups (work history)';
COMMENT ON COLUMN contacts.volunteer_experiences IS 'JSONB array of volunteer experiences';
COMMENT ON COLUMN contacts.languages IS 'JSONB array of languages';
COMMENT ON COLUMN contacts.skills IS 'JSONB array of skills';
COMMENT ON COLUMN contacts.recommendations IS 'JSONB array of recommendations';
COMMENT ON COLUMN contacts.network_info IS 'JSONB object containing network information';
COMMENT ON COLUMN contacts.analysis IS 'JSONB object containing complete analysis including model, source, score, selling, hiring, and assessments data';
COMMENT ON COLUMN contacts.activities IS 'JSONB object containing social media activities and content posts';
COMMENT ON COLUMN contacts.contact_id_from_api IS 'Contact ID from the API response for tracking purposes';
COMMENT ON COLUMN contacts.company_id_from_api IS 'Company ID from the API response for tracking purposes';
COMMENT ON COLUMN contacts.extraction_timestamp IS 'Timestamp when the data was extracted from the API'; 