-- RI-2 indexing integrity.
--
-- Adds a bounded, operator-safe indexing failure detail owned by selltonai-modal.
-- selltonai reads this field to explain failed indexing and offer a retry. The
-- migration and both application changes must be released together.

ALTER TABLE public.organization_files
    ADD COLUMN IF NOT EXISTS error_detail text;

COMMENT ON COLUMN public.organization_files.error_detail IS
    'Bounded, non-secret summary of the latest document indexing failure. Cleared after a successful retry.';

ALTER TABLE public.organization_files
    DROP CONSTRAINT IF EXISTS organization_files_error_detail_length_check;

ALTER TABLE public.organization_files
    ADD CONSTRAINT organization_files_error_detail_length_check
    CHECK (error_detail IS NULL OR char_length(error_detail) <= 500);
