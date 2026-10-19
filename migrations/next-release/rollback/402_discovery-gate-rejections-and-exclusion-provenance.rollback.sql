-- Reverses 402. The Modal code tolerates the missing table and columns (it logs and goes on),
-- so this can run while the gate is live; the gate then has no memory of earlier rejections.
DROP TABLE IF EXISTS public.discovery_rejections;

ALTER TABLE public.organization_icp_linkedin_urls
  DROP CONSTRAINT IF EXISTS organization_icp_linkedin_urls_source_check;
ALTER TABLE public.organization_icp_linkedin_urls
  DROP COLUMN IF EXISTS source,
  DROP COLUMN IF EXISTS reason,
  DROP COLUMN IF EXISTS source_company_id,
  DROP COLUMN IF EXISTS source_campaign_id;
