-- Re-enable the file upload trigger
DROP TRIGGER IF EXISTS trg_handle_file_upload ON public.organization_files;
CREATE TRIGGER trg_handle_file_upload
AFTER INSERT ON public.organization_files
FOR EACH ROW EXECUTE PROCEDURE public.notify_handle_file_upload(); 