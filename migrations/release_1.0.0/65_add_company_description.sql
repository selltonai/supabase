-- Migration to add company_description column

-- 1. Add new column
ALTER TABLE public.organization_settings
  ADD COLUMN IF NOT EXISTS company_description TEXT;

-- 2. Add comment for new column
COMMENT ON COLUMN public.organization_settings.company_description IS 'The description of the company and its activities.'; 