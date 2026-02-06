-- Migration: Create campaign_seed_companies table for tracking lookalike discovery
-- Description: Tracks which seed companies are used for lookalike discovery and their pagination state
-- Author: System
-- Date: 2025-11-19

-- Create campaign_seed_companies table
CREATE TABLE IF NOT EXISTS campaign_seed_companies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id uuid NOT NULL REFERENCES campaigns(id) ON DELETE CASCADE,
  organization_id text NOT NULL REFERENCES organization(id) ON DELETE CASCADE,
  
  -- Seed company information
  seed_company_url text NOT NULL, -- LinkedIn URL of the seed company
  seed_company_name text, -- Company name for reference
  seed_company_id text, -- B2B ID (e.g., b2b-79476549) if available
  
  -- Pagination tracking
  current_page integer NOT NULL DEFAULT 0, -- Current page being processed (0-indexed)
  total_pages_found integer, -- Total pages available for this seed company
  total_elements_found integer, -- Total companies found for this seed company
  
  -- Processing state
  is_active boolean NOT NULL DEFAULT false, -- Which seed company we're currently processing
  is_completed boolean NOT NULL DEFAULT false, -- Whether we've finished all pages for this seed company
  
  -- Ordering
  processing_order integer NOT NULL DEFAULT 0, -- Order in which seed companies should be processed
  
  -- Timestamps
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  
  -- Constraints
  UNIQUE (campaign_id, seed_company_url)
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_campaign_seed_companies_campaign_id ON campaign_seed_companies(campaign_id);
CREATE INDEX IF NOT EXISTS idx_campaign_seed_companies_organization_id ON campaign_seed_companies(organization_id);
CREATE INDEX IF NOT EXISTS idx_campaign_seed_companies_is_active ON campaign_seed_companies(campaign_id, is_active) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_campaign_seed_companies_processing_order ON campaign_seed_companies(campaign_id, processing_order);

-- Documentation comments
COMMENT ON TABLE campaign_seed_companies IS 'Tracks seed companies used for lookalike discovery and their pagination state';
COMMENT ON COLUMN campaign_seed_companies.seed_company_url IS 'LinkedIn URL of the seed company used for lookalike discovery';
COMMENT ON COLUMN campaign_seed_companies.current_page IS 'Current page number being processed (0-indexed)';
COMMENT ON COLUMN campaign_seed_companies.total_pages_found IS 'Total number of pages available for this seed company';
COMMENT ON COLUMN campaign_seed_companies.total_elements_found IS 'Total number of companies found for this seed company';
COMMENT ON COLUMN campaign_seed_companies.is_active IS 'Indicates which seed company is currently being processed';
COMMENT ON COLUMN campaign_seed_companies.is_completed IS 'Indicates whether all pages have been processed for this seed company';
COMMENT ON COLUMN campaign_seed_companies.processing_order IS 'Order in which seed companies should be processed (0 = first, 1 = second, etc.)';







