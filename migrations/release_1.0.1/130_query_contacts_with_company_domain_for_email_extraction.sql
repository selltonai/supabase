-- Query to find all contacts that haven't been sent for email extraction yet
-- This query includes company domain information from company_contacts relationships
-- 
-- Returns contacts that:
-- - Don't have an email address (email IS NULL)
-- - Haven't had email extraction attempted (email_validation_response IS NULL)
-- - Have a company relationship (via company_contacts table)
-- - Have firstname and lastname (required for email extraction)
-- - Have a company with website (required for domain extraction)

SELECT 
  c.id,
  c.organization_id,
  c.name,
  c.firstname,
  c.lastname,
  c.email,
  c.linkedin_url,
  c.headline,
  c.email_validation_response,
  c.b2b_email_requested,
  c.created_at,
  c.updated_at,
  -- Company information
  comp.id AS company_id,
  comp.name AS company_name,
  comp.website AS company_website,
  -- Extract domain from website (handles various URL formats)
  CASE 
    WHEN comp.website IS NOT NULL AND comp.website != '' THEN 
      REGEXP_REPLACE(
        REGEXP_REPLACE(
          REGEXP_REPLACE(comp.website, '^https?://', '', 'g'),
          '^www\.',
          '',
          'g'
        ),
        '/.*$',
        '',
        'g'
      )
    ELSE NULL
  END AS extracted_domain,
  cc.created_at AS company_contact_created_at
FROM public.contacts c
INNER JOIN public.company_contacts cc ON c.id = cc.contact_id AND c.organization_id = cc.organization_id
INNER JOIN public.companies comp ON cc.company_id = comp.id AND c.organization_id = comp.organization_id
WHERE 
  -- Contact doesn't have an email
  c.email IS NULL
  -- Email extraction hasn't been attempted yet
  AND c.email_validation_response IS NULL
  -- Has firstname and lastname (required for email extraction)
  AND c.firstname IS NOT NULL 
  AND c.firstname != ''
  AND c.lastname IS NOT NULL 
  AND c.lastname != ''
  -- Company has website
  AND comp.website IS NOT NULL 
  AND comp.website != ''
ORDER BY c.created_at DESC;

-- Optional: Add organization filter
-- WHERE 
--   c.organization_id = 'your-organization-id'
--   AND c.email IS NULL
--   AND c.email_validation_response IS NULL
--   ...

-- Optional: Count query
-- SELECT COUNT(*) as contacts_needing_email_extraction
-- FROM public.contacts c
-- INNER JOIN public.company_contacts cc ON c.id = cc.contact_id AND c.organization_id = cc.organization_id
-- INNER JOIN public.companies comp ON cc.company_id = comp.id AND c.organization_id = comp.organization_id
-- WHERE 
--   c.email IS NULL
--   AND c.email_validation_response IS NULL
--   AND c.firstname IS NOT NULL 
--   AND c.firstname != ''
--   AND c.lastname IS NOT NULL 
--   AND c.lastname != ''
--   AND comp.website IS NOT NULL 
--   AND comp.website != '';

-- Optional: Group by domain to see distribution
-- SELECT 
--   REGEXP_REPLACE(
--     REGEXP_REPLACE(
--       REGEXP_REPLACE(comp.website, '^https?://', '', 'g'),
--       '^www\.',
--       '',
--       'g'
--     ),
--     '/.*$',
--     '',
--     'g'
--   ) AS domain,
--   COUNT(*) as contact_count
-- FROM public.contacts c
-- INNER JOIN public.company_contacts cc ON c.id = cc.contact_id AND c.organization_id = cc.organization_id
-- INNER JOIN public.companies comp ON cc.company_id = comp.id AND c.organization_id = comp.organization_id
-- WHERE 
--   c.email IS NULL
--   AND c.email_validation_response IS NULL
--   AND c.firstname IS NOT NULL 
--   AND c.firstname != ''
--   AND c.lastname IS NOT NULL 
--   AND c.lastname != ''
--   AND comp.website IS NOT NULL 
--   AND comp.website != ''
-- GROUP BY domain
-- ORDER BY contact_count DESC;

