-- Reverses 405. Deploy the Modal revert first: a Modal build that calls bump_verification_digest gets
-- "function does not exist" (42883) and loses the verification notification until it is reverted.
-- Digest rows already written stay in public.notifications as ordinary notifications.
DROP FUNCTION IF EXISTS public.bump_verification_digest(text, text, text, text, text, text, integer);
DROP FUNCTION IF EXISTS public.verification_digest_title(text, integer, text);
