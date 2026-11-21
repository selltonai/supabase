-- Reverses 451. Not lossy: a switch_to_full request becomes a feedback request with details.kind 'switch_to_full'.
-- Ship the app commit that stops writing the type first.
SET LOCAL lock_timeout = '10s';

ALTER TABLE public.customer_requests DROP CONSTRAINT IF EXISTS customer_requests_type_check;

UPDATE public.customer_requests
   SET type = 'feedback',
       details = details || jsonb_build_object('kind', 'switch_to_full')
 WHERE type = 'switch_to_full';

ALTER TABLE public.customer_requests
  ADD CONSTRAINT customer_requests_type_check
  CHECK (type IN ('feedback', 'mailboxes', 'leave', 'trial_extension'));

COMMENT ON COLUMN public.customer_requests.type IS
  'feedback | mailboxes | leave | trial_extension (439: the customer asks for more trial time; body is their reason).';
