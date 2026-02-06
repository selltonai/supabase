CREATE OR REPLACE FUNCTION public.notify_handle_file_upload()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _url text := 'https://hook.eu2.make.com/z62vlfyhd9sl6oi4rqtbqugy6g9ha7b3';
BEGIN
  PERFORM net.http_post(
    url := _url,
    body := jsonb_build_object('record', to_jsonb(NEW)),
    headers := '{"Content-Type": "application/json"}'::jsonb
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_handle_file_upload ON public.organization_files;
CREATE TRIGGER trg_handle_file_upload
AFTER INSERT ON public.organization_files
FOR EACH ROW EXECUTE FUNCTION public.notify_handle_file_upload();