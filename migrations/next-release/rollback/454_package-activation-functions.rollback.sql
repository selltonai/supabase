-- Reverses 454. Ship the app commits that stop calling the functions first: the webhook, the wall and Settings then
-- get "function does not exist" for a package purchase or a code. Not lossy: the rows the functions wrote
-- (activation_fees, workspace_allowances, cs_recommendations, package_codes, package_code_attempts) stay as they are.
SET LOCAL lock_timeout = '10s';

DROP FUNCTION IF EXISTS public.end_package_grant_for_payment(text, text, integer, integer);
DROP FUNCTION IF EXISTS public.redeem_package_code(text, text, text, text);
DROP FUNCTION IF EXISTS public.activate_package_checkout(text, text, text, integer, text, text, text);
