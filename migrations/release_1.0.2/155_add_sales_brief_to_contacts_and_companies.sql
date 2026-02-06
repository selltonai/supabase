-- Migration: Add sales_brief column to contacts and companies tables
-- Description: Adds sales_brief TEXT column to store sales brief information as markdown directly in CRM profiles
-- Author: System
-- Date: 2025-01-XX

-- Add sales_brief column to contacts table (TEXT for markdown)
ALTER TABLE contacts 
  ADD COLUMN IF NOT EXISTS sales_brief TEXT DEFAULT NULL;

-- Add sales_brief column to companies table (TEXT for markdown)
ALTER TABLE companies 
  ADD COLUMN IF NOT EXISTS sales_brief TEXT DEFAULT NULL;

-- Add comments for documentation
COMMENT ON COLUMN contacts.sales_brief IS 'Sales brief information stored as markdown text. Contains key information about the contact for sales purposes. Users can edit this directly.';
COMMENT ON COLUMN companies.sales_brief IS 'Sales brief information stored as markdown text. Contains key information about the company for sales purposes. Users can edit this directly.';

-- Add indexes for efficient querying (text search index)
CREATE INDEX IF NOT EXISTS idx_contacts_sales_brief ON contacts(sales_brief) WHERE sales_brief IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_companies_sales_brief ON companies(sales_brief) WHERE sales_brief IS NOT NULL;

