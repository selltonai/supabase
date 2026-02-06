-- Migration: Add CSV template upload tracking column to campaigns table
-- Description: Adds csv_template_upload boolean column to track if campaign uses template CSV format
-- Date: 2025-01-XX

-- Add csv_template_upload column to campaigns table
ALTER TABLE public.campaigns
ADD COLUMN IF NOT EXISTS csv_template_upload boolean NOT NULL DEFAULT false;

-- Add comment to explain the column
COMMENT ON COLUMN public.campaigns.csv_template_upload IS 'Indicates whether the campaign uses template CSV format (with First Name, Last Name, etc.) vs regular company-only CSV format';

-- Create index for filtering campaigns by CSV template upload type
CREATE INDEX IF NOT EXISTS idx_campaigns_csv_template_upload ON public.campaigns(organization_id, csv_template_upload)
WHERE csv_template_upload = true;

