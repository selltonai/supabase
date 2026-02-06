-- Migration: Add b2b_result JSONB column to companies table
-- Description: Adds b2b_result field to store B2B API response data for companies
-- Author: System
-- Date: 2025-01-20

-- Add b2b_result JSONB column to companies table
ALTER TABLE companies 
  ADD COLUMN IF NOT EXISTS b2b_result JSONB;

-- Create GIN index for efficient JSONB queries
CREATE INDEX IF NOT EXISTS idx_companies_b2b_result ON companies USING GIN (b2b_result);

-- Add comment for documentation
COMMENT ON COLUMN companies.b2b_result IS 'Stores B2B API response data for the company including enrichment details, contact information, and other structured data from external B2B services';
