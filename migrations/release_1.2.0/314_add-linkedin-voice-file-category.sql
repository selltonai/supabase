-- ============================================================
-- Add LinkedIn voice as a Knowledge Brain file category
-- Projects:
--   - selltonai: upload UI can store organization_files.file_category='linkedin_voice'
--   - selltonai-modal: document analysis and knowledge search accepts the category
--   - selltonai-vector-api: Pinecone metadata/search accepts the category
-- App changes required together:
--   - Deploy enum/category updates in all three services before exposing uploads.
-- Notes:
--   - This is an enum value addition only; existing rows and vectors are unchanged.
-- ============================================================

ALTER TYPE public.file_category_enum ADD VALUE IF NOT EXISTS 'linkedin_voice';

COMMENT ON COLUMN public.organization_files.file_category IS
  'Category of the file: documents, transcripts, linkedin_voice, internal_documents, sales_papers, sait_guidelines, brand_guidelines, case_study, sales_scripts, images, presentations, spreadsheets, proposals, other';
