-- Reverses 379. Safe while play_messages, mobile_scheduled_actions and mobile_send_counters are empty
-- (true until mobile S6a). Check first:
--   SELECT (SELECT count(*) FROM public.play_messages) AS pm,
--          (SELECT count(*) FROM public.mobile_scheduled_actions) AS msa,
--          (SELECT count(*) FROM public.mobile_send_counters) AS msc;
DROP TRIGGER IF EXISTS mobile_send_counters_updated_at ON public.mobile_send_counters;
DROP TRIGGER IF EXISTS mobile_scheduled_actions_updated_at ON public.mobile_scheduled_actions;
DROP FUNCTION IF EXISTS public.update_mobile_send_counters_updated_at();
DROP FUNCTION IF EXISTS public.update_mobile_scheduled_actions_updated_at();
DROP FUNCTION IF EXISTS public.mobile_reserve_sends(text, text, date, integer, integer);
DROP TABLE IF EXISTS public.mobile_send_counters;
DROP TABLE IF EXISTS public.mobile_scheduled_actions;
DROP TABLE IF EXISTS public.play_messages;
-- No companies/contacts change to reverse: the Brain columns ship with KAN-270, not with 379.
-- organization.mobile and organization.signup_source are kept on purpose (see above). To remove them,
-- revert the webhook's change first, then:
-- ALTER TABLE public.organization DROP COLUMN IF EXISTS signup_source, DROP COLUMN IF EXISTS mobile;
