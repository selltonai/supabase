-- Manual cleanup for organization_files rows that timed out during app deletion.
-- Run in Supabase SQL Editor against production project hufnufdmbeenfhgvpesi.
-- Scope: Sellton workspace only.

CREATE OR REPLACE FUNCTION public.remove_deleted_file_from_companies()
RETURNS trigger AS $$
BEGIN
  IF current_setting('sellton.skip_file_delete_company_cleanup', true) = 'on' THEN
    RETURN NULL;
  END IF;

  UPDATE public.companies
     SET useful_case_file_ids = array_remove(useful_case_file_ids, OLD.id),
         updated_at = NOW()
   WHERE organization_id = OLD.organization_id
     AND useful_case_file_ids @> ARRAY[OLD.id]::uuid[];

  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

BEGIN;

SET LOCAL statement_timeout = '60s';

CREATE TEMP TABLE requested_file_ids (
  input_id uuid PRIMARY KEY
) ON COMMIT DROP;

CREATE TEMP TABLE stuck_organization_files (
  file_id uuid PRIMARY KEY
) ON COMMIT DROP;

CREATE TEMP TABLE cleanup_file_ids (
  file_id uuid PRIMARY KEY
) ON COMMIT DROP;

INSERT INTO requested_file_ids (input_id)
VALUES
  ('a3bf181f-cb98-4349-b6ae-22a7cebcc02c'::uuid),
  ('6576f163-6adb-4f08-86d0-205c35c20f87'::uuid),
  ('91d978f9-e40f-4483-9ab6-f14bfa6b45ba'::uuid),
  ('9d3189b8-c76b-4cbc-a105-ca229630e2c3'::uuid),
  ('d4a84ed5-985b-44ff-9cc9-0583ffb80eaa'::uuid),
  ('eabf380c-20f3-4a2a-8fe8-b3cf5edae4fe'::uuid)
ON CONFLICT (input_id) DO NOTHING;

INSERT INTO stuck_organization_files (file_id)
SELECT files.id
FROM public.organization_files files
JOIN requested_file_ids requested ON requested.input_id = files.id
WHERE files.organization_id = 'org_33gYRWEGYoY2NJy4Imdc5VBdvbu'
ON CONFLICT (file_id) DO NOTHING;

INSERT INTO stuck_organization_files (file_id)
SELECT campaign_files.file_id
FROM public.campaign_files campaign_files
JOIN requested_file_ids requested ON requested.input_id = campaign_files.id
JOIN public.organization_files files ON files.id = campaign_files.file_id
WHERE campaign_files.file_id IS NOT NULL
  AND files.organization_id = 'org_33gYRWEGYoY2NJy4Imdc5VBdvbu'
ON CONFLICT (file_id) DO NOTHING;

INSERT INTO cleanup_file_ids (file_id)
SELECT input_id FROM requested_file_ids
ON CONFLICT (file_id) DO NOTHING;

INSERT INTO cleanup_file_ids (file_id)
SELECT file_id FROM stuck_organization_files
ON CONFLICT (file_id) DO NOTHING;

DELETE FROM public.document_access_events events
USING cleanup_file_ids cleanup
WHERE events.file_id = cleanup.file_id
  AND events.organization_id = 'org_33gYRWEGYoY2NJy4Imdc5VBdvbu';

DELETE FROM public.document_short_urls urls
USING cleanup_file_ids cleanup
WHERE urls.file_id = cleanup.file_id
  AND urls.organization_id = 'org_33gYRWEGYoY2NJy4Imdc5VBdvbu';

DELETE FROM public.campaign_files campaign_files
USING cleanup_file_ids cleanup
WHERE campaign_files.file_id = cleanup.file_id
   OR campaign_files.id = cleanup.file_id;

UPDATE public.companies companies
   SET useful_case_file_ids = array_remove(companies.useful_case_file_ids, stuck.file_id),
       updated_at = NOW()
  FROM stuck_organization_files stuck
 WHERE companies.organization_id = 'org_33gYRWEGYoY2NJy4Imdc5VBdvbu'
   AND companies.useful_case_file_ids @> ARRAY[stuck.file_id]::uuid[];

SELECT set_config('sellton.skip_file_delete_company_cleanup', 'on', true);

DELETE FROM public.organization_files files
USING stuck_organization_files stuck
WHERE files.id = stuck.file_id
  AND files.organization_id = 'org_33gYRWEGYoY2NJy4Imdc5VBdvbu';

SELECT files.id, files.file_name
FROM public.organization_files files
JOIN stuck_organization_files stuck ON stuck.file_id = files.id
WHERE files.organization_id = 'org_33gYRWEGYoY2NJy4Imdc5VBdvbu';

SELECT campaign_files.id, campaign_files.file_id, campaign_files.file_name
FROM public.campaign_files campaign_files
JOIN cleanup_file_ids cleanup
  ON campaign_files.id = cleanup.file_id
  OR campaign_files.file_id = cleanup.file_id;

COMMIT;
