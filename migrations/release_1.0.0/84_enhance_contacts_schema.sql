-- Migration: Enhance Contacts Schema for Rich Contact Data
-- Purpose: Add support for B2B contact enrichment, LinkedIn data, personality analysis, and communication insights
-- Date: 2025-01-13

-- Add new columns to contacts table for enhanced contact data
ALTER TABLE contacts 
  -- LinkedIn and professional data
  ADD COLUMN IF NOT EXISTS linkedin_url TEXT,
  ADD COLUMN IF NOT EXISTS linkedin_identifier TEXT,
  ADD COLUMN IF NOT EXISTS entity_urn TEXT,
  ADD COLUMN IF NOT EXISTS object_urn TEXT,
  ADD COLUMN IF NOT EXISTS headline TEXT,
  ADD COLUMN IF NOT EXISTS profile_picture TEXT,
  ADD COLUMN IF NOT EXISTS background_image TEXT,
  ADD COLUMN IF NOT EXISTS is_premium BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS is_influencer BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS is_open_to_work BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS professional_summary TEXT,
  
  -- Location details (enhanced)
  ADD COLUMN IF NOT EXISTS location_default_value TEXT, -- Full location string
  ADD COLUMN IF NOT EXISTS location_short_value TEXT, -- Short location string
  
  -- Education and experience
  ADD COLUMN IF NOT EXISTS education JSONB, -- Array of education records
  ADD COLUMN IF NOT EXISTS work_history JSONB, -- Array of work experience
  ADD COLUMN IF NOT EXISTS current_company_info JSONB, -- Current company details
  ADD COLUMN IF NOT EXISTS industries_worked_in TEXT[], -- Array of industries
  ADD COLUMN IF NOT EXISTS skills TEXT[], -- Array of skills
  ADD COLUMN IF NOT EXISTS languages TEXT[], -- Array of languages
  
  -- Personality and communication analysis
  ADD COLUMN IF NOT EXISTS personality_archetype TEXT, -- e.g., "Pioneer", "Diplomat"
  ADD COLUMN IF NOT EXISTS communication_types TEXT[], -- e.g., ["high dominance", "high influence"]
  ADD COLUMN IF NOT EXISTS communication_adjectives TEXT[], -- e.g., ["Motivated Yet Thoughtful"]
  ADD COLUMN IF NOT EXISTS ocean_traits JSONB, -- Big Five personality traits
  ADD COLUMN IF NOT EXISTS disc_traits JSONB, -- DISC personality assessment
  
  -- Sales and communication insights
  ADD COLUMN IF NOT EXISTS decision_drivers TEXT[], -- What influences their decisions
  ADD COLUMN IF NOT EXISTS risk_appetite TEXT, -- Risk tolerance description
  ADD COLUMN IF NOT EXISTS ability_to_say_no TEXT, -- How they handle rejection
  ADD COLUMN IF NOT EXISTS decision_speed TEXT, -- How quickly they make decisions
  ADD COLUMN IF NOT EXISTS communication_what_to_say TEXT[], -- Communication guidelines
  ADD COLUMN IF NOT EXISTS communication_what_to_avoid TEXT[], -- Communication warnings
  
  -- Email and outreach guidelines
  ADD COLUMN IF NOT EXISTS email_guidelines JSONB, -- Email writing guidelines
  ADD COLUMN IF NOT EXISTS hiring_guidelines JSONB, -- Hiring/recruitment guidelines
  
  -- Social media and content
  ADD COLUMN IF NOT EXISTS content_posts JSONB, -- Recent LinkedIn posts and engagement
  ADD COLUMN IF NOT EXISTS social_activity_score INTEGER, -- Social media activity level
  
  -- B2B enrichment metadata
  ADD COLUMN IF NOT EXISTS b2b_result JSONB, -- Full B2B enrichment API response
  ADD COLUMN IF NOT EXISTS enrichment_timestamp TIMESTAMPTZ, -- When data was enriched
  ADD COLUMN IF NOT EXISTS enrichment_score INTEGER, -- Quality score of enrichment (0-100)
  ADD COLUMN IF NOT EXISTS data_sources TEXT[], -- Sources of data (LinkedIn, etc.)
  
  -- Analysis and scoring
  ADD COLUMN IF NOT EXISTS fit_score_detailed JSONB, -- Detailed fit scoring breakdown
  ADD COLUMN IF NOT EXISTS lead_quality_score INTEGER, -- Overall lead quality (0-100)
  ADD COLUMN IF NOT EXISTS engagement_likelihood DECIMAL(3,2), -- Likelihood to engage (0-1)
  
  -- Processing status
  ADD COLUMN IF NOT EXISTS processing_status TEXT DEFAULT 'pending', -- pending, processing, completed, failed
  ADD COLUMN IF NOT EXISTS enrichment_source TEXT; -- Source of enrichment data

-- Create indexes for performance on new columns
CREATE INDEX IF NOT EXISTS idx_contacts_linkedin_url ON contacts(linkedin_url);
CREATE INDEX IF NOT EXISTS idx_contacts_linkedin_identifier ON contacts(linkedin_identifier);
CREATE INDEX IF NOT EXISTS idx_contacts_entity_urn ON contacts(entity_urn);
CREATE INDEX IF NOT EXISTS idx_contacts_personality_archetype ON contacts(personality_archetype);
CREATE INDEX IF NOT EXISTS idx_contacts_lead_quality_score ON contacts(lead_quality_score);
CREATE INDEX IF NOT EXISTS idx_contacts_engagement_likelihood ON contacts(engagement_likelihood);
CREATE INDEX IF NOT EXISTS idx_contacts_processing_status ON contacts(processing_status);
CREATE INDEX IF NOT EXISTS idx_contacts_enrichment_timestamp ON contacts(enrichment_timestamp);
CREATE INDEX IF NOT EXISTS idx_contacts_enrichment_source ON contacts(enrichment_source);
CREATE INDEX IF NOT EXISTS idx_contacts_is_open_to_work ON contacts(is_open_to_work);

-- Create GIN indexes for JSONB columns
CREATE INDEX IF NOT EXISTS idx_contacts_b2b_result_gin ON contacts USING GIN (b2b_result);
CREATE INDEX IF NOT EXISTS idx_contacts_education_gin ON contacts USING GIN (education);
CREATE INDEX IF NOT EXISTS idx_contacts_work_history_gin ON contacts USING GIN (work_history);
CREATE INDEX IF NOT EXISTS idx_contacts_current_company_info_gin ON contacts USING GIN (current_company_info);
CREATE INDEX IF NOT EXISTS idx_contacts_ocean_traits_gin ON contacts USING GIN (ocean_traits);
CREATE INDEX IF NOT EXISTS idx_contacts_disc_traits_gin ON contacts USING GIN (disc_traits);
CREATE INDEX IF NOT EXISTS idx_contacts_email_guidelines_gin ON contacts USING GIN (email_guidelines);
CREATE INDEX IF NOT EXISTS idx_contacts_hiring_guidelines_gin ON contacts USING GIN (hiring_guidelines);
CREATE INDEX IF NOT EXISTS idx_contacts_content_posts_gin ON contacts USING GIN (content_posts);
CREATE INDEX IF NOT EXISTS idx_contacts_fit_score_detailed_gin ON contacts USING GIN (fit_score_detailed);

-- Create indexes for array columns
CREATE INDEX IF NOT EXISTS idx_contacts_communication_types_gin ON contacts USING GIN (communication_types);
CREATE INDEX IF NOT EXISTS idx_contacts_skills_gin ON contacts USING GIN (skills);
CREATE INDEX IF NOT EXISTS idx_contacts_industries_worked_in_gin ON contacts USING GIN (industries_worked_in);
CREATE INDEX IF NOT EXISTS idx_contacts_languages_gin ON contacts USING GIN (languages);
CREATE INDEX IF NOT EXISTS idx_contacts_data_sources_gin ON contacts USING GIN (data_sources);

-- Add comments for documentation
COMMENT ON COLUMN contacts.linkedin_url IS 'LinkedIn profile URL';
COMMENT ON COLUMN contacts.linkedin_identifier IS 'LinkedIn profile identifier/slug';
COMMENT ON COLUMN contacts.entity_urn IS 'LinkedIn entity URN identifier';
COMMENT ON COLUMN contacts.object_urn IS 'LinkedIn object URN identifier';
COMMENT ON COLUMN contacts.headline IS 'Professional headline from LinkedIn';
COMMENT ON COLUMN contacts.profile_picture IS 'URL to profile picture';
COMMENT ON COLUMN contacts.background_image IS 'URL to LinkedIn background image';
COMMENT ON COLUMN contacts.is_premium IS 'Whether contact has LinkedIn Premium';
COMMENT ON COLUMN contacts.is_influencer IS 'Whether contact is a LinkedIn influencer';
COMMENT ON COLUMN contacts.is_open_to_work IS 'Whether contact is open to work opportunities';
COMMENT ON COLUMN contacts.professional_summary IS 'Professional summary/bio from LinkedIn';
COMMENT ON COLUMN contacts.location_default_value IS 'Full location string';
COMMENT ON COLUMN contacts.location_short_value IS 'Shortened location string';
COMMENT ON COLUMN contacts.education IS 'Array of education records with school, degree, field of study';
COMMENT ON COLUMN contacts.work_history IS 'Array of work experience records';
COMMENT ON COLUMN contacts.current_company_info IS 'Current company details and position';
COMMENT ON COLUMN contacts.industries_worked_in IS 'Array of industries the contact has worked in';
COMMENT ON COLUMN contacts.skills IS 'Array of professional skills';
COMMENT ON COLUMN contacts.languages IS 'Array of languages spoken';
COMMENT ON COLUMN contacts.personality_archetype IS 'Personality archetype classification (e.g., Pioneer, Diplomat)';
COMMENT ON COLUMN contacts.communication_types IS 'Array of communication style types';
COMMENT ON COLUMN contacts.communication_adjectives IS 'Array of communication style adjectives';
COMMENT ON COLUMN contacts.ocean_traits IS 'Big Five personality traits (Openness, Conscientiousness, Extraversion, Agreeableness, Neuroticism)';
COMMENT ON COLUMN contacts.disc_traits IS 'DISC personality assessment (Dominance, Influence, Steadiness, Conscientiousness)';
COMMENT ON COLUMN contacts.decision_drivers IS 'Array of factors that influence their decision making';
COMMENT ON COLUMN contacts.risk_appetite IS 'Description of risk tolerance and appetite';
COMMENT ON COLUMN contacts.ability_to_say_no IS 'How they handle rejection and saying no';
COMMENT ON COLUMN contacts.decision_speed IS 'How quickly they typically make decisions';
COMMENT ON COLUMN contacts.communication_what_to_say IS 'Array of recommended communication approaches';
COMMENT ON COLUMN contacts.communication_what_to_avoid IS 'Array of communication approaches to avoid';
COMMENT ON COLUMN contacts.email_guidelines IS 'Email writing guidelines including tone, length, structure';
COMMENT ON COLUMN contacts.hiring_guidelines IS 'Guidelines for recruiting/hiring communications';
COMMENT ON COLUMN contacts.content_posts IS 'Recent LinkedIn posts and engagement data';
COMMENT ON COLUMN contacts.social_activity_score IS 'Social media activity level score (0-100)';
COMMENT ON COLUMN contacts.b2b_result IS 'Full B2B enrichment API response data';
COMMENT ON COLUMN contacts.enrichment_timestamp IS 'Timestamp when contact data was enriched';
COMMENT ON COLUMN contacts.enrichment_score IS 'Quality score of data enrichment (0-100)';
COMMENT ON COLUMN contacts.data_sources IS 'Array of data sources used for enrichment';
COMMENT ON COLUMN contacts.fit_score_detailed IS 'Detailed breakdown of fit scoring components';
COMMENT ON COLUMN contacts.lead_quality_score IS 'Overall lead quality score (0-100)';
COMMENT ON COLUMN contacts.engagement_likelihood IS 'Likelihood to engage with outreach (0-1)';
COMMENT ON COLUMN contacts.processing_status IS 'Status of contact data processing';
COMMENT ON COLUMN contacts.enrichment_source IS 'Source of enrichment data (API, manual, etc.)';

-- Create a function to calculate lead quality score based on various factors
CREATE OR REPLACE FUNCTION calculate_lead_quality_score()
RETURNS TRIGGER AS $$
BEGIN
  -- Calculate lead quality score based on available data
  NEW.lead_quality_score := COALESCE(
    (
      -- Base score from fit_score (0-40 points)
      COALESCE(NEW.fit_score * 0.4, 0) +
      
      -- Enrichment completeness (0-20 points)
      CASE 
        WHEN NEW.enrichment_score IS NOT NULL THEN NEW.enrichment_score * 0.2
        ELSE 0
      END +
      
      -- LinkedIn data availability (0-20 points)
      CASE 
        WHEN NEW.linkedin_url IS NOT NULL THEN 10
        ELSE 0
      END +
      CASE 
        WHEN NEW.professional_summary IS NOT NULL THEN 5
        ELSE 0
      END +
      CASE 
        WHEN NEW.work_history IS NOT NULL THEN 5
        ELSE 0
      END +
      
      -- Engagement indicators (0-20 points)
      CASE 
        WHEN NEW.is_open_to_work = TRUE THEN 10
        ELSE 0
      END +
      CASE 
        WHEN NEW.social_activity_score > 50 THEN 10
        ELSE NEW.social_activity_score * 0.2
      END
    ), 0
  );
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to automatically calculate lead quality score
DROP TRIGGER IF EXISTS trigger_calculate_lead_quality_score ON contacts;
CREATE TRIGGER trigger_calculate_lead_quality_score
  BEFORE INSERT OR UPDATE ON contacts
  FOR EACH ROW
  EXECUTE FUNCTION calculate_lead_quality_score();

-- Create a view for contact analytics
CREATE OR REPLACE VIEW contact_analytics AS
SELECT 
  c.id,
  c.organization_id,
  c.company_id,
  c.name,
  c.email,
  c.job_title,
  c.company_name,
  c.linkedin_url,
  c.headline,
  c.contact_type,
  c.status,
  c.fit_score,
  c.lead_quality_score,
  c.engagement_likelihood,
  c.personality_archetype,
  c.is_open_to_work,
  c.enrichment_score,
  c.processing_status,
  c.created_at,
  c.enrichment_timestamp,
  
  -- Extract key personality traits
  (c.ocean_traits->>'openness')::DECIMAL AS openness_score,
  (c.ocean_traits->>'conscientiousness')::DECIMAL AS conscientiousness_score,
  (c.ocean_traits->>'extraversion')::DECIMAL AS extraversion_score,
  (c.ocean_traits->>'agreeableness')::DECIMAL AS agreeableness_score,
  (c.ocean_traits->>'emotionalStability')::DECIMAL AS emotional_stability_score,
  
  (c.disc_traits->>'dominance')::DECIMAL AS dominance_score,
  (c.disc_traits->>'influence')::DECIMAL AS influence_score,
  (c.disc_traits->>'steadiness')::DECIMAL AS steadiness_score,
  (c.disc_traits->>'calculativeness')::DECIMAL AS calculativeness_score,
  
  -- Company information
  comp.name AS company_name_from_table,
  comp.industry AS company_industry,
  comp.employee_count,
  comp.icp_score_total AS company_icp_score
  
FROM contacts c
LEFT JOIN companies comp ON comp.id = c.company_id;

COMMENT ON VIEW contact_analytics IS 'Analytics view for contact data with extracted personality traits and company information'; 