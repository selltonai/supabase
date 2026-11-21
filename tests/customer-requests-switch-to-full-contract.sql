-- Migration 451's contract: customer_requests takes 'switch_to_full', keeps every earlier type, and still refuses an
-- unknown one. Run by tests/run-customer-requests-switch-to-full-contract.sh on a disposable database, after 391,
-- 439 and 451.
DO $$
DECLARE r record;
BEGIN
  INSERT INTO public.customer_requests (organization_id, user_id, type, body)
  VALUES ('org_a', 'user_1', 'switch_to_full', 'We want plays on the web too') RETURNING * INTO r;
  IF r.status <> 'new' OR r.details <> '{}'::jsonb THEN RAISE EXCEPTION 'bad defaults: %', row_to_json(r); END IF;
  INSERT INTO public.customer_requests (organization_id, user_id, type) VALUES ('org_a', 'user_1', 'switch_to_full');
  FOREACH r.type IN ARRAY ARRAY['feedback', 'mailboxes', 'leave', 'trial_extension'] LOOP
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

-- The rollback keeps every request: switch_to_full rows become feedback rows with details.kind 'switch_to_full'.
BEGIN;
\i migrations/next-release/rollback/451_customer-requests-switch-to-full.rollback.sql
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM public.customer_requests WHERE type = 'switch_to_full') THEN RAISE EXCEPTION 'rollback left the type'; END IF;
  IF (SELECT count(*) FROM public.customer_requests WHERE type = 'feedback' AND details->>'kind' = 'switch_to_full') <> 2 THEN
    RAISE EXCEPTION 'rollback lost a switch to full request';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.customer_requests WHERE type = 'trial_extension') THEN
    RAISE EXCEPTION 'rollback touched a trial extension request';
  END IF;
  BEGIN
    INSERT INTO public.customer_requests (organization_id, user_id, type) VALUES ('org_a', 'u', 'switch_to_full');
    RAISE EXCEPTION 'the rolled-back CHECK accepted switch_to_full';
  EXCEPTION WHEN check_violation THEN NULL; END;
END $$;
ROLLBACK;
SELECT 'customer_requests switch_to_full contract passed' AS result;
