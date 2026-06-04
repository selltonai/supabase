-- Optimize organization file deletion cleanup.
-- What changed: make the companies.useful_case_file_ids cleanup trigger use the
-- existing GIN array index and constrain updates to the deleted file's workspace.
-- Projects affected: selltonai file deletion, selltonai-modal company context reads.
-- Application impact: no request/response contract change; deletes stop timing out
-- when a workspace has many company rows.

CREATE INDEX IF NOT EXISTS idx_companies_useful_case_file_ids
  ON public.companies USING GIN (useful_case_file_ids);

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

CREATE OR REPLACE FUNCTION public.delete_organization_file_fast(
  p_file_id uuid,
  p_organization_id text
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  deleted_count integer := 0;
BEGIN
  DELETE FROM public.campaign_files
   WHERE file_id = p_file_id;

  DELETE FROM public.document_short_urls
   WHERE file_id = p_file_id
     AND organization_id = p_organization_id;

  UPDATE public.companies
     SET useful_case_file_ids = array_remove(useful_case_file_ids, p_file_id),
         updated_at = NOW()
   WHERE organization_id = p_organization_id
     AND useful_case_file_ids @> ARRAY[p_file_id]::uuid[];

  PERFORM set_config('sellton.skip_file_delete_company_cleanup', 'on', true);

  DELETE FROM public.organization_files
   WHERE id = p_file_id
     AND organization_id = p_organization_id;

  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  RETURN deleted_count > 0;
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_organization_file_fast(uuid, text) TO service_role;
