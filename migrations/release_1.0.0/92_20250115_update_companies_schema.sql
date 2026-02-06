-- Migration: Update Companies Schema to Match API Response Format
-- Description: Updates companies table to match the exact format from the API response and removes unnecessary fields
-- Author: System
-- Date: 2025-01-15

-- First, add new columns that are missing
ALTER TABLE companies 
  ADD COLUMN IF NOT EXISTS universal_name TEXT,
  ADD COLUMN IF NOT EXISTS company_type TEXT,
  ADD COLUMN IF NOT EXISTS cover TEXT,
  ADD COLUMN IF NOT EXISTS tagline TEXT,
  ADD COLUMN IF NOT EXISTS founded_year INTEGER,
  ADD COLUMN IF NOT EXISTS object_urn BIGINT,
  ADD COLUMN IF NOT EXISTS followers INTEGER,
  ADD COLUMN IF NOT EXISTS locations JSONB DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS funding_data JSONB DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS specialities TEXT[] DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS industries TEXT[] DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS hashtags TEXT[] DEFAULT '{}';

-- Rename existing columns to match the format
DO $$ 
BEGIN
  -- Rename logo_url to logo if it exists
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'logo_url') THEN
    ALTER TABLE companies RENAME COLUMN logo_url TO logo;
  END IF;
  
  -- Rename size_category to size if it exists
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'size_category') THEN
    ALTER TABLE companies RENAME COLUMN size_category TO size;
  END IF;
  
  -- Rename type to company_type if it exists
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'type') THEN
    ALTER TABLE companies RENAME COLUMN type TO company_type;
  END IF;
  
  -- Rename founded_year_old to founded_year if it exists (in case there's an old column)
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'founded_year_old') THEN
    ALTER TABLE companies RENAME COLUMN founded_year_old TO founded_year;
  END IF;
  
  -- Rename object_urn_old to object_urn if it exists (in case there's an old column)
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'object_urn_old') THEN
    ALTER TABLE companies RENAME COLUMN object_urn_old TO object_urn;
  END IF;
END $$;

-- Remove unnecessary fields that weren't mentioned in requirements
DO $$ 
BEGIN
  -- Remove state column if it exists
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'state') THEN
    ALTER TABLE companies DROP COLUMN state;
  END IF;
  
  -- Remove country column if it exists
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'country') THEN
    ALTER TABLE companies DROP COLUMN country;
  END IF;
  
  -- Remove headquarters column if it exists
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'headquarters') THEN
    ALTER TABLE companies DROP COLUMN headquarters;
  END IF;
  
  -- Remove city column if it exists
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'city') THEN
    ALTER TABLE companies DROP COLUMN city;
  END IF;
  
  -- Remove region column if it exists
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'region') THEN
    ALTER TABLE companies DROP COLUMN region;
  END IF;
  
  -- Remove postal_code column if it exists
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'postal_code') THEN
    ALTER TABLE companies DROP COLUMN postal_code;
  END IF;
  
  -- Remove address column if it exists
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'address') THEN
    ALTER TABLE companies DROP COLUMN address;
  END IF;
  
  -- Remove revenue column if it exists
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'revenue') THEN
    ALTER TABLE companies DROP COLUMN revenue;
  END IF;
  
  -- Remove annual_revenue column if it exists
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'annual_revenue') THEN
    ALTER TABLE companies DROP COLUMN annual_revenue;
  END IF;
  
  -- Remove twitter_url column if it exists
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'twitter_url') THEN
    ALTER TABLE companies DROP COLUMN twitter_url;
  END IF;
  
  -- Remove facebook_url column if it exists
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'facebook_url') THEN
    ALTER TABLE companies DROP COLUMN facebook_url;
  END IF;
  
  -- Remove cover_image_url column if it exists (we have cover instead)
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'cover_image_url') THEN
    ALTER TABLE companies DROP COLUMN cover_image_url;
  END IF;
  
  -- Remove specialties column if it exists (we have specialities instead)
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'specialties') THEN
    ALTER TABLE companies DROP COLUMN specialties;
  END IF;
  
  -- Remove tech_stack column if it exists
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'tech_stack') THEN
    ALTER TABLE companies DROP COLUMN tech_stack;
  END IF;
  
  -- Remove funding_stage column if it exists (we have funding_data instead)
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'funding_stage') THEN
    ALTER TABLE companies DROP COLUMN funding_stage;
  END IF;
  
  -- Remove total_funding column if it exists (we have funding_data instead)
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'total_funding') THEN
    ALTER TABLE companies DROP COLUMN total_funding;
  END IF;
  
  -- Remove last_funding_date column if it exists (we have funding_data instead)
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'last_funding_date') THEN
    ALTER TABLE companies DROP COLUMN last_funding_date;
  END IF;
  
  -- Remove last_funding_round column if it exists (we have funding_data instead)
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'last_funding_round') THEN
    ALTER TABLE companies DROP COLUMN last_funding_round;
  END IF;
  
  -- Remove investors column if it exists (we have funding_data instead)
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'investors') THEN
    ALTER TABLE companies DROP COLUMN investors;
  END IF;
  
  -- Remove crunchbase_url column if it exists
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'crunchbase_url') THEN
    ALTER TABLE companies DROP COLUMN crunchbase_url;
  END IF;
  
  -- Remove bloomberg_url column if it exists
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'bloomberg_url') THEN
    ALTER TABLE companies DROP COLUMN bloomberg_url;
  END IF;
  
  -- Remove stock_symbol column if it exists
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'stock_symbol') THEN
    ALTER TABLE companies DROP COLUMN stock_symbol;
  END IF;
  
  -- Remove public_private column if it exists
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'public_private') THEN
    ALTER TABLE companies DROP COLUMN public_private;
  END IF;
  
  -- Remove tags column if it exists
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'tags') THEN
    ALTER TABLE companies DROP COLUMN tags;
  END IF;
  
  -- Remove notes column if it exists
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'notes') THEN
    ALTER TABLE companies DROP COLUMN notes;
  END IF;
  
  -- Remove linkedin_followers column if it exists (we have followers instead)
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'linkedin_followers') THEN
    ALTER TABLE companies DROP COLUMN linkedin_followers;
  END IF;
  
  -- Remove twitter_followers column if it exists (we have followers instead)
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'twitter_followers') THEN
    ALTER TABLE companies DROP COLUMN twitter_followers;
  END IF;
  
  -- Remove total_funding_amount column if it exists (we have funding_data instead)
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'total_funding_amount') THEN
    ALTER TABLE companies DROP COLUMN total_funding_amount;
  END IF;
  
  -- Remove competitors column if it exists
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'competitors') THEN
    ALTER TABLE companies DROP COLUMN competitors;
  END IF;
  
  -- Remove followers_count column if it exists (we have followers instead)
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'followers_count') THEN
    ALTER TABLE companies DROP COLUMN followers_count;
  END IF;
  
  -- Remove key_insights column if it exists
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'key_insights') THEN
    ALTER TABLE companies DROP COLUMN key_insights;
  END IF;
  
  -- Remove custom_fields column if it exists
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'custom_fields') THEN
    ALTER TABLE companies DROP COLUMN custom_fields;
  END IF;
  
  -- Remove extraction_timestamp column if it exists
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'extraction_timestamp') THEN
    ALTER TABLE companies DROP COLUMN extraction_timestamp;
  END IF;
  
  -- Remove processing_duration column if it exists
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'processing_duration') THEN
    ALTER TABLE companies DROP COLUMN processing_duration;
  END IF;
  
  -- Remove first_outreach_date column if it exists
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'first_outreach_date') THEN
    ALTER TABLE companies DROP COLUMN first_outreach_date;
  END IF;
  
  -- Remove last_outreach_date column if it exists
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'last_outreach_date') THEN
    ALTER TABLE companies DROP COLUMN last_outreach_date;
  END IF;
  
  -- Remove outreach_count column if it exists
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'outreach_count') THEN
    ALTER TABLE companies DROP COLUMN outreach_count;
  END IF;
  
  -- Remove outreach_campaigns column if it exists
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'companies' AND column_name = 'outreach_campaigns') THEN
    ALTER TABLE companies DROP COLUMN outreach_campaigns;
  END IF;
END $$;

-- Update the companies table to have the exact structure from the API
-- The final structure should be:
-- Core fields:
-- id, organization_id, created_at, updated_at (system fields)
-- name, universal_name, company_type, website, linkedin_url, description, industry, size, phone, location, employee_count (basic info)
-- logo, cover, tagline, founded_year, object_urn, followers (branding/social)
-- locations, funding_data, specialities, industries, hashtags (structured data)
-- icp_score, deep_research (analysis data)

-- Add comment to table
COMMENT ON TABLE companies IS 'Companies table with cleaned schema matching API response format'; 