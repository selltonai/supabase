-- Reverses 439. Not lossy: a trial_extension request becomes a feedback request with details.kind 'trial_extension',
-- which the backoffice still reads as a trial extension request. Ship the app commit that stops writing the type first.
SET LOCAL lock_timeout = '10s';

ALTER TABLE public.customer_requests DROP CONSTRAINT IF EXISTS customer_requests_type_check;

UPDATE public.customer_requests
   SET type = 'feedback',
       details = details || jsonb_build_object('kind', 'trial_extension')
 WHERE type = 'trial_extension';

ALTER TABLE public.customer_requests
  ADD CONSTRAINT customer_requests_type_check
  CHECK (type IN ('feedback', 'mailboxes', 'leave'));

COMMENT ON COLUMN public.customer_requests.type IS NULL;
