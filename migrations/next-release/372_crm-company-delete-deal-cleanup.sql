-- KAN-304: prepare deal/task cleanup before company foreign-key cascades.
-- Owner: selltonai-database/supabase. Consumers: selltonai-modal CRM list
-- deletion and selltonai company deletion. No coordinated app update required.
-- Requires migration 370 (delete_crm_deal). Request/response and auth unchanged.

CREATE OR REPLACE FUNCTION public.prepare_crm_company_deletion()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_deal_id UUID;
BEGIN
  -- Without this ordering, the company FK can clear tasks.company_id after
  -- deals have cascaded away but before tasks.deal_id has been cleared. The
  -- task scope validator then rejects an otherwise valid company deletion.
  FOR v_deal_id IN
    SELECT id FROM public.deals
    WHERE company_id = OLD.id AND organization_id = OLD.organization_id
    ORDER BY id
  LOOP
    PERFORM public.delete_crm_deal(OLD.organization_id, v_deal_id, NULL);
  END LOOP;

  RETURN OLD;
END;
$$;

REVOKE ALL ON FUNCTION public.prepare_crm_company_deletion() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_prepare_crm_company_deletion ON public.companies;
CREATE TRIGGER trg_prepare_crm_company_deletion
  BEFORE DELETE ON public.companies
  FOR EACH ROW
  EXECUTE FUNCTION public.prepare_crm_company_deletion();
