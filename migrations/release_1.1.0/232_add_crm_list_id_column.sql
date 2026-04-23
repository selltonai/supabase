-- Migration: Add crm_list_id to companies table
-- Description: Add field to track which CRM list a company came from for filtering
-- Author: System
-- Date: 2026-04-02

-- Add crm_list_id column to companies table
ALTER TABLE companies 
ADD COLUMN crm_list_id TEXT;

-- Add index for performance on CRM list filtering
CREATE INDEX idx_companies_crm_list_id ON companies(crm_list_id) WHERE crm_list_id IS NOT NULL;

-- Add comment explaining the new field
COMMENT ON COLUMN companies.crm_list_id IS 'ID of the CRM list this company was imported from, for filtering and tracking purposes';
