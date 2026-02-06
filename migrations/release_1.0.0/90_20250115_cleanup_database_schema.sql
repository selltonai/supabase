-- Migration: Clean up database schema to only keep essential fields
-- Description: Removes unnecessary fields from companies and contacts tables
-- Author: System
-- Date: 2025-01-15

-- Clean up companies table - remove unnecessary fields
DO $$ 
BEGIN
    -- Remove unnecessary company fields
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'universal_name') THEN
        ALTER TABLE companies DROP COLUMN universal_name;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'company_type') THEN
        ALTER TABLE companies DROP COLUMN company_type;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'tagline') THEN
        ALTER TABLE companies DROP COLUMN tagline;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'founded_year') THEN
        ALTER TABLE companies DROP COLUMN founded_year;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'object_urn') THEN
        ALTER TABLE companies DROP COLUMN object_urn;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'followers_count') THEN
        ALTER TABLE companies DROP COLUMN followers_count;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'cover_image_url') THEN
        ALTER TABLE companies DROP COLUMN cover_image_url;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'funding_data') THEN
        ALTER TABLE companies DROP COLUMN funding_data;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'funding_stage') THEN
        ALTER TABLE companies DROP COLUMN funding_stage;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'total_funding_amount') THEN
        ALTER TABLE companies DROP COLUMN total_funding_amount;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'competitors') THEN
        ALTER TABLE companies DROP COLUMN competitors;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'tech_stack') THEN
        ALTER TABLE companies DROP COLUMN tech_stack;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'twitter_url') THEN
        ALTER TABLE companies DROP COLUMN twitter_url;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'facebook_url') THEN
        ALTER TABLE companies DROP COLUMN facebook_url;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'instagram_url') THEN
        ALTER TABLE companies DROP COLUMN instagram_url;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'youtube_url') THEN
        ALTER TABLE companies DROP COLUMN youtube_url;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'postal_code') THEN
        ALTER TABLE companies DROP COLUMN postal_code;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'address_line1') THEN
        ALTER TABLE companies DROP COLUMN address_line1;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'address_line2') THEN
        ALTER TABLE companies DROP COLUMN address_line2;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'geographic_area') THEN
        ALTER TABLE companies DROP COLUMN geographic_area;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'is_primary_location') THEN
        ALTER TABLE companies DROP COLUMN is_primary_location;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'locations') THEN
        ALTER TABLE companies DROP COLUMN locations;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'company_size_category') THEN
        ALTER TABLE companies DROP COLUMN company_size_category;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'revenue_range') THEN
        ALTER TABLE companies DROP COLUMN revenue_range;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'annual_revenue') THEN
        ALTER TABLE companies DROP COLUMN annual_revenue;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'recent_news') THEN
        ALTER TABLE companies DROP COLUMN recent_news;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'growth_signals') THEN
        ALTER TABLE companies DROP COLUMN growth_signals;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'funding_history') THEN
        ALTER TABLE companies DROP COLUMN funding_history;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'company_profile') THEN
        ALTER TABLE companies DROP COLUMN company_profile;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'competitive_landscape') THEN
        ALTER TABLE companies DROP COLUMN competitive_landscape;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'recent_developments') THEN
        ALTER TABLE companies DROP COLUMN recent_developments;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'domain') THEN
        ALTER TABLE companies DROP COLUMN domain;
    END IF;
END $$;

-- Clean up contacts table - remove unnecessary fields
DO $$ 
BEGIN
    -- Remove unnecessary contact fields
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'contacts' AND column_name = 'birth_date') THEN
        ALTER TABLE contacts DROP COLUMN birth_date;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'contacts' AND column_name = 'background_image') THEN
        ALTER TABLE contacts DROP COLUMN background_image;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'contacts' AND column_name = 'is_open_to_work') THEN
        ALTER TABLE contacts DROP COLUMN is_open_to_work;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'contacts' AND column_name = 'is_influencer') THEN
        ALTER TABLE contacts DROP COLUMN is_influencer;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'contacts' AND column_name = 'is_premium') THEN
        ALTER TABLE contacts DROP COLUMN is_premium;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'contacts' AND column_name = 'entity_urn') THEN
        ALTER TABLE contacts DROP COLUMN entity_urn;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'contacts' AND column_name = 'object_urn') THEN
        ALTER TABLE contacts DROP COLUMN object_urn;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'contacts' AND column_name = 'linkedin_identifier') THEN
        ALTER TABLE contacts DROP COLUMN linkedin_identifier;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'contacts' AND column_name = 'organizations') THEN
        ALTER TABLE contacts DROP COLUMN organizations;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'contacts' AND column_name = 'patents') THEN
        ALTER TABLE contacts DROP COLUMN patents;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'contacts' AND column_name = 'awards') THEN
        ALTER TABLE contacts DROP COLUMN awards;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'contacts' AND column_name = 'projects') THEN
        ALTER TABLE contacts DROP COLUMN projects;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'contacts' AND column_name = 'publications') THEN
        ALTER TABLE contacts DROP COLUMN publications;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'contacts' AND column_name = 'courses') THEN
        ALTER TABLE contacts DROP COLUMN courses;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'contacts' AND column_name = 'test_scores') THEN
        ALTER TABLE contacts DROP COLUMN test_scores;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'contacts' AND column_name = 'volunteer_experiences') THEN
        ALTER TABLE contacts DROP COLUMN volunteer_experiences;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'contacts' AND column_name = 'recommendations') THEN
        ALTER TABLE contacts DROP COLUMN recommendations;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'contacts' AND column_name = 'network_info') THEN
        ALTER TABLE contacts DROP COLUMN network_info;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'contacts' AND column_name = 'position_groups') THEN
        ALTER TABLE contacts DROP COLUMN position_groups;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'contacts' AND column_name = 'work_history') THEN
        ALTER TABLE contacts DROP COLUMN work_history;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'contacts' AND column_name = 'industries_worked_in') THEN
        ALTER TABLE contacts DROP COLUMN industries_worked_in;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'contacts' AND column_name = 'current_company') THEN
        ALTER TABLE contacts DROP COLUMN current_company;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'contacts' AND column_name = 'current_companies') THEN
        ALTER TABLE contacts DROP COLUMN current_companies;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'contacts' AND column_name = 'personality_traits') THEN
        ALTER TABLE contacts DROP COLUMN personality_traits;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'contacts' AND column_name = 'communication_types') THEN
        ALTER TABLE contacts DROP COLUMN communication_types;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'contacts' AND column_name = 'key_traits') THEN
        ALTER TABLE contacts DROP COLUMN key_traits;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'contacts' AND column_name = 'icp_insights') THEN
        ALTER TABLE contacts DROP COLUMN icp_insights;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'contacts' AND column_name = 'writing_guidelines') THEN
        ALTER TABLE contacts DROP COLUMN writing_guidelines;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'contacts' AND column_name = 'content_posts') THEN
        ALTER TABLE contacts DROP COLUMN content_posts;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'contacts' AND column_name = 'professional_summary') THEN
        ALTER TABLE contacts DROP COLUMN professional_summary;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'contacts' AND column_name = 'industry') THEN
        ALTER TABLE contacts DROP COLUMN industry;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'contacts' AND column_name = 'tags') THEN
        ALTER TABLE contacts DROP COLUMN tags;
    END IF;
    
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'contacts' AND column_name = 'extraction_timestamp') THEN
        ALTER TABLE contacts DROP COLUMN extraction_timestamp;
    END IF;
END $$;

-- Keep only essential fields for companies:
-- id, name, website, linkedin_url, description, industry, size, phone, location, employee_count, logo_url, cover_image_url, industries, icp_score, deep_research, key_insights, created_at, updated_at, organization_id

-- Keep only essential fields for contacts:
-- id, name, email, linkedin_url, firstname, lastname, headline, profile_picture, summary, location, current_company_name, current_position_title, educations, certifications, position_groups, languages, skills, selling_analysis, hiring_analysis, assessments, activities, company_id, created_at, updated_at, organization_id

-- Update comments to reflect the cleaned up schema
COMMENT ON TABLE companies IS 'Stores essential company information for campaigns';
COMMENT ON TABLE contacts IS 'Stores essential contact information linked to companies';

-- Add indexes for better performance on essential fields
CREATE INDEX IF NOT EXISTS idx_companies_industry ON companies(industry);
CREATE INDEX IF NOT EXISTS idx_companies_employee_count ON companies(employee_count);
CREATE INDEX IF NOT EXISTS idx_contacts_current_company ON contacts(current_company_name);
CREATE INDEX IF NOT EXISTS idx_contacts_headline ON contacts(headline);
CREATE INDEX IF NOT EXISTS idx_contacts_company_id ON contacts(company_id); 