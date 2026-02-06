-- Update storage bucket to allow text/plain and application/octet-stream files
-- This is needed because some CSV and TXT files are detected as application/octet-stream

UPDATE storage.buckets 
SET allowed_mime_types = ARRAY[
  'application/pdf', 
  'application/msword', 
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 
  'text/csv', 
  'text/plain',
  'application/octet-stream'
]::text[]
WHERE id = 'organization-files'; 