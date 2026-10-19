-- The type CHECK as both lines have it today: 361's list plus 376's 'call_due'. This is 376's own DO block, copied
-- because the rest of 376 needs the CRM tables. Disposable database only.
DO $$
DECLARE v_expression text;
BEGIN
  SELECT pg_get_expr(conbin, conrelid) INTO STRICT v_expression
  FROM pg_constraint WHERE conrelid='public.notifications'::regclass
    AND conname='notifications_type_check';
  IF position('call_due' IN v_expression)=0 THEN
    ALTER TABLE public.notifications DROP CONSTRAINT notifications_type_check;
    EXECUTE 'ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check CHECK ((' || v_expression || ') OR type = ''call_due'')';
  END IF;
END $$;
