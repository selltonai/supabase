-- KAN-322 FR-B7 contract for migration 398: has_inbound on hand-worked threads. Disposable database only.
INSERT INTO public.linkedin_threads (organization_id, unipile_chat_id, last_direction) VALUES
  ('org_a', 'cold', 'outbound'),        -- we wrote, nobody answered
  ('org_a', 'answered', 'outbound'),    -- they wrote, we answered: Replied
  ('org_a', 'waiting', 'inbound'),      -- they wrote last: Needs reply
  ('org_a', 'empty', NULL),             -- no messages stored
  ('org_a', 'other-org-reply', 'outbound'); -- an inbound message with the same chat id in another workspace only
INSERT INTO public.linkedin_messages (organization_id, unipile_chat_id, direction) VALUES
  ('org_a', 'cold', 'outbound'), ('org_a', 'cold', 'outbound'),
  ('org_a', 'answered', 'outbound'), ('org_a', 'answered', 'inbound'), ('org_a', 'answered', 'outbound'),
  ('org_a', 'waiting', 'outbound'), ('org_a', 'waiting', 'inbound'),
  ('org_a', 'other-org-reply', 'outbound'), ('org_b', 'other-org-reply', 'inbound'),
  ('org_a', NULL, 'inbound');

DO $$
DECLARE
  got text;
BEGIN
  SELECT string_agg(t.unipile_chat_id || '=' || public.has_inbound(t)::text, ',' ORDER BY t.unipile_chat_id) INTO got
  FROM public.linkedin_threads t;
  IF got IS DISTINCT FROM 'answered=true,cold=false,empty=false,other-org-reply=false,waiting=true' THEN
    RAISE EXCEPTION 'has_inbound per thread: %', got;
  END IF;

  -- Replied, as the BFF asks for it: last_direction = outbound and has_inbound.
  SELECT string_agg(t.unipile_chat_id, ',' ORDER BY t.unipile_chat_id) INTO got
  FROM public.linkedin_threads t WHERE t.last_direction = 'outbound' AND public.has_inbound(t);
  IF got IS DISTINCT FROM 'answered' THEN
    RAISE EXCEPTION 'Replied: %', got;
  END IF;

  -- The computed-field form PostgREST uses (t.has_inbound) resolves to the function.
  SELECT string_agg(t.unipile_chat_id, ',' ORDER BY t.unipile_chat_id) INTO got
  FROM public.linkedin_threads t WHERE t.has_inbound;
  IF got IS DISTINCT FROM 'answered,waiting' THEN
    RAISE EXCEPTION 'computed field form: %', got;
  END IF;

  IF has_function_privilege('anon', 'public.has_inbound(public.linkedin_threads)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.has_inbound(public.linkedin_threads)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.has_inbound(public.linkedin_threads)', 'EXECUTE') THEN
    RAISE EXCEPTION 'has_inbound privileges';
  END IF;

  -- STABLE and SQL: inlined into the caller's query (no per-row function call overhead).
  IF (SELECT provolatile FROM pg_proc WHERE proname = 'has_inbound') <> 's' THEN
    RAISE EXCEPTION 'has_inbound must be STABLE';
  END IF;
END $$;
