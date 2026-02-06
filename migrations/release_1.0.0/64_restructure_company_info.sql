-- Migration to restructure company_info from JSONB to individual columns

-- 1. Add new columns
ALTER TABLE public.organization_settings
  ADD COLUMN IF NOT EXISTS company_website TEXT,
  ADD COLUMN IF NOT EXISTS company_linkedin_profile TEXT;

-- 2. Migrate data from company_info JSONB to new columns
DO $$
DECLARE
  org_setting RECORD;
BEGIN
  -- Check if company_info column exists before proceeding
  IF EXISTS (
    SELECT 1 
    FROM information_schema.columns 
    WHERE table_name = 'organization_settings' 
    AND column_name = 'company_info'
  ) THEN
    FOR org_setting IN 
      SELECT id, company_info
      FROM public.organization_settings
      WHERE company_info IS NOT NULL AND jsonb_typeof(company_info) = 'object'
    LOOP
      UPDATE public.organization_settings
      SET 
        company_website = org_setting.company_info->>'website',
        company_linkedin_profile = org_setting.company_info->>'linkedin_profile'
      WHERE id = org_setting.id;
    END LOOP;
  END IF;
END $$;

-- 3. Drop the old company_info column
ALTER TABLE public.organization_settings
  DROP COLUMN IF EXISTS company_info;

-- 4. Add comments for new columns
COMMENT ON COLUMN public.organization_settings.company_website IS 'The official website of the company.';
COMMENT ON COLUMN public.organization_settings.company_linkedin_profile IS 'The LinkedIn profile URL of the company.'; 