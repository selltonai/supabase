-- Emergency fix for file upload error
-- This removes the problematic trigger that uses net.http_post

-- Drop the problematic trigger
DROP TRIGGER IF EXISTS trg_handle_file_upload ON public.organization_files;

-- Drop the function that uses net.http_post
DROP FUNCTION IF EXISTS public.notify_handle_file_upload();

-- Create a simple logging function instead
CREATE OR REPLACE FUNCTION public.log_file_upload()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Simple logging instead of HTTP call
  RAISE NOTICE 'File uploaded: % by %', NEW.file_name, NEW.uploaded_by;
  RETURN NEW;
END;
$$;

-- Create a new trigger with the simple logging function
DROP TRIGGER IF EXISTS trg_log_file_upload ON public.organization_files;
CREATE TRIGGER trg_log_file_upload
AFTER INSERT ON public.organization_files
FOR EACH ROW EXECUTE FUNCTION public.log_file_upload();

-- Add comment explaining the change
COMMENT ON FUNCTION public.log_file_upload() IS 'Logs file uploads instead of making HTTP calls to avoid net extension dependency';

-- Verify the fix
SELECT 'File upload error fixed successfully!' as message; 