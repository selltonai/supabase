-- Reverses 424. Deploy the Modal code without P5 and P6 first: the router writes goal_campaign_id and the LinkedIn
-- writer writes step_key, and both fail while the columns are gone.
SET LOCAL lock_timeout = '10s';

ALTER TABLE public.company_signal_contact_use
  DROP COLUMN IF EXISTS step_key;

ALTER TABLE public.company_signal_workspace
  DROP COLUMN IF EXISTS goal_campaign_id;
