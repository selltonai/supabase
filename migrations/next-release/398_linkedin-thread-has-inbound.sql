-- KAN-322 FR-B7: whether a LinkedIn thread has an inbound message, for the Inbox's "Replied" (they wrote at some point
-- and our message is the newest: last_direction = 'outbound' and has_inbound). A PostgREST computed field: the BFF
-- filters threads with `has_inbound=is.true` in the same request that lists them, so totals and paging stay exact.
--
-- Messages are matched on the thread's chat and organization (linkedin_messages has no foreign key to threads; the
-- chat id is unique per thread). The existing idx_linkedin_messages_chat (unipile_chat_id, occurred_at) serves the
-- lookup. Read-only, additive and safe to drop. Called with the service role only (the BFF); anon and authenticated
-- are revoked, as every new public function here.

CREATE OR REPLACE FUNCTION public.has_inbound(thread public.linkedin_threads)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.linkedin_messages m
    WHERE m.unipile_chat_id = thread.unipile_chat_id
      AND m.organization_id = thread.organization_id
      AND m.direction = 'inbound'
  );
$$;

REVOKE ALL ON FUNCTION public.has_inbound(public.linkedin_threads) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.has_inbound(public.linkedin_threads) TO service_role;

COMMENT ON FUNCTION public.has_inbound(public.linkedin_threads) IS
  'KAN-322 FR-B7: true when the thread has an inbound message in linkedin_messages (same chat, same organization). PostgREST computed field for the Inbox''s Replied tab; service role only.';

DO $$
BEGIN
  IF has_function_privilege('anon', 'public.has_inbound(public.linkedin_threads)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.has_inbound(public.linkedin_threads)', 'EXECUTE') THEN
    RAISE EXCEPTION '398: anon or authenticated can still execute has_inbound';
  END IF;
END $$;

-- Verify (read-only):
-- SELECT has_function_privilege('anon', 'public.has_inbound(public.linkedin_threads)', 'EXECUTE') AS anon_exec,          -- false
--        has_function_privilege('service_role', 'public.has_inbound(public.linkedin_threads)', 'EXECUTE') AS service_exec; -- true
-- SELECT t.unipile_chat_id, t.last_direction, public.has_inbound(t) FROM public.linkedin_threads t ORDER BY t.last_message_at DESC LIMIT 5;
