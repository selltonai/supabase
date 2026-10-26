-- Reverses 411. Play lists stay as ordinary lists (source campaign_output, no play link); their
-- members stay, marked 'manual' so the old CHECK holds. The web reads campaign_id only when it is
-- there, so the app keeps working without it.
SET LOCAL lock_timeout = '10s';

DROP TRIGGER IF EXISTS play_list_after_company_links ON public.campaign_companies;
DROP TRIGGER IF EXISTS play_list_after_contact_links ON public.campaign_contacts;
DROP TRIGGER IF EXISTS play_list_after_campaign_update ON public.campaigns;

DROP FUNCTION IF EXISTS public.play_list_after_company_links();
DROP FUNCTION IF EXISTS public.play_list_after_contact_links();
DROP FUNCTION IF EXISTS public.play_list_after_campaign_update();
DROP FUNCTION IF EXISTS public.play_list_fill(text, uuid);
DROP FUNCTION IF EXISTS public.add_play_list_members(text, uuid, uuid[], uuid[]);
DROP FUNCTION IF EXISTS public.get_companies_by_list(text, uuid, text, text, text, text, integer, integer, text, uuid);

UPDATE public.crm_list_members SET source = 'manual' WHERE source = 'play';
ALTER TABLE public.crm_list_members
  DROP CONSTRAINT IF EXISTS crm_list_members_source_check;
ALTER TABLE public.crm_list_members
  ADD CONSTRAINT crm_list_members_source_check
  CHECK (source IN ('manual', 'campaign_selection'));

DROP INDEX IF EXISTS public.idx_crm_lists_campaign_id_unique;
ALTER TABLE public.crm_lists
  DROP COLUMN IF EXISTS campaign_id;
