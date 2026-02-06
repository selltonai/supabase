-- Query to find all contacts that haven't been sent for email extraction yet
-- This query ignores the b2b_email_requested flag and checks email_validation_response instead
-- 
-- Logic:
-- - email IS NULL: Contact doesn't have an email address
-- - email_validation_response IS NULL: No email extraction attempt has been made yet
--   (email_validation_response is populated when email extraction API is called)

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
  c.created_at,
  c.updated_at
FROM public.contacts c
WHERE 
  c.email IS NULL
  AND c.email_validation_response IS NULL
ORDER BY c.created_at DESC;

-- Optional: Add organization filter if needed
-- WHERE 
--   c.organization_id = 'your-organization-id'
--   AND c.email IS NULL
--   AND c.email_validation_response IS NULL

-- Optional: Count query
-- SELECT COUNT(*) as contacts_needing_email_extraction
-- FROM public.contacts c
-- WHERE 
--   c.email IS NULL
--   AND c.email_validation_response IS NULL;















