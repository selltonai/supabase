-- Reverses 423. The backoffice treats the missing functions as "not deployed" and builds the same rows from the
-- tables; without the two columns it reads every member as never seen and without marketing consent.
-- Lossy once a writer ships: dropping the columns drops the last-seen times and the consent times written after 423.
-- Copy public.user_profiles (user_id, organization_id, last_seen_at, consent_marketing_at) first if any are set.
DROP FUNCTION IF EXISTS public.backoffice_cs_workspace_facts_v1(text);
DROP FUNCTION IF EXISTS public.backoffice_cs_segment_inputs_v1();

ALTER TABLE public.user_profiles
  DROP COLUMN IF EXISTS consent_marketing_at,
  DROP COLUMN IF EXISTS last_seen_at;
