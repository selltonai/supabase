-- Reverses 422. The backoffice treats the missing tables and column as "feature not deployed": the agent's pages
-- show nothing and the lifecycle emails run as before 422.
-- A step that uses one of the two new audiences cannot keep it: it is switched off and set back to not_activated,
-- so it sends nothing until someone looks at it.
UPDATE public.email_sequence_steps
SET is_active = false,
    audience_mode = 'not_activated'
WHERE audience_mode IN ('chase', 'segment');

ALTER TABLE public.email_sequence_steps
  DROP CONSTRAINT IF EXISTS email_sequence_steps_audience_mode_check;
ALTER TABLE public.email_sequence_steps
  ADD CONSTRAINT email_sequence_steps_audience_mode_check
  CHECK (audience_mode IN ('not_activated', 'funnel_stage'));

ALTER TABLE public.email_sequence_steps
  DROP CONSTRAINT IF EXISTS email_sequence_steps_signup_source_check;
ALTER TABLE public.email_sequence_steps
  DROP COLUMN IF EXISTS signup_source;

COMMENT ON COLUMN public.email_sequence_steps.audience_mode IS
  'not_activated: all orgs without activation/card, gated by org age >= delay. funnel_stage: legacy find_funnel_dropouts targeting.';

DROP TABLE IF EXISTS public.cs_costs;
DROP TABLE IF EXISTS public.cs_recommendations;
DROP TABLE IF EXISTS public.cs_briefs;
DROP TABLE IF EXISTS public.cs_messages;
DROP TABLE IF EXISTS public.cs_threads;
