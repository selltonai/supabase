-- Migration 439's contract: customer_requests takes 'trial_extension', and still refuses an unknown type. Run by
-- tests/run-customer-requests-trial-extension-contract.sh on a disposable database, after 391 and 439.
DO $$
DECLARE r record;
BEGIN
  INSERT INTO public.customer_requests (organization_id, user_id, type, body)
  VALUES ('org_a', 'user_1', 'trial_extension', 'We need one more week to launch') RETURNING * INTO r;
  IF r.status <> 'new' OR r.details <> '{}'::jsonb THEN RAISE EXCEPTION 'bad defaults: %', row_to_json(r); END IF;
  INSERT INTO public.customer_requests (organization_id, user_id, type) VALUES ('org_a', 'user_1', 'trial_extension');
  FOREACH r.type IN ARRAY ARRAY['feedback', 'mailboxes', 'leave'] LOOP
    INSERT INTO public.customer_requests (organization_id, user_id, type) VALUES ('org_a', 'u', r.type);
  END LOOP;
  BEGIN
    INSERT INTO public.customer_requests (organization_id, user_id, type) VALUES ('org_a', 'u', 'refund');
    RAISE EXCEPTION 'an unknown type was accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;
  IF (SELECT count(*) FROM pg_constraint WHERE conrelid = 'public.customer_requests'::regclass AND contype = 'c'
        AND pg_get_constraintdef(oid) LIKE '%type%' AND conname = 'customer_requests_type_check') <> 1 THEN
    RAISE EXCEPTION 'expected exactly one type CHECK named customer_requests_type_check';
  END IF;
END $$;

-- The rollback keeps every request: trial_extension rows become feedback rows with details.kind 'trial_extension'.
BEGIN;
\i migrations/next-release/rollback/439_customer-requests-trial-extension.rollback.sql
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM public.customer_requests WHERE type = 'trial_extension') THEN RAISE EXCEPTION 'rollback left the type'; END IF;
  IF (SELECT count(*) FROM public.customer_requests WHERE type = 'feedback' AND details->>'kind' = 'trial_extension') <> 2 THEN
    RAISE EXCEPTION 'rollback lost a trial extension request';
  END IF;
  BEGIN
    INSERT INTO public.customer_requests (organization_id, user_id, type) VALUES ('org_a', 'u', 'trial_extension');
    RAISE EXCEPTION 'the rolled-back CHECK accepted trial_extension';
  EXCEPTION WHEN check_violation THEN NULL; END;
END $$;
ROLLBACK;
SELECT 'customer_requests trial_extension contract passed' AS result;
