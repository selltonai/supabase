-- Update storage bucket to allow text/plain files
UPDATE storage.buckets 
SET allowed_mime_types = ARRAY['application/pdf', 'application/msword', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'text/csv', 'text/plain']::text[]
WHERE id = 'organization-files'; 