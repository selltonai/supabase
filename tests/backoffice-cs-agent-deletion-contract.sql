-- Migration 428's contract. Run by tests/run-backoffice-cs-agent-deletion-contract.sh on a disposable database.

-- refuses(sql, sqlstate, what): the statement must fail with exactly that error (23514 check, 23505 unique).
CREATE FUNCTION pg_temp.refuses(p_sql text, p_state text, p_what text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE got text;
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN others THEN got := SQLSTATE;
  END;
  IF got IS NULL THEN RAISE EXCEPTION 'accepted: %', p_what; END IF;
  IF got <> p_state THEN RAISE EXCEPTION 'refused with % instead of %: %', got, p_state, p_what; END IF;
END $$;

-- Access: the service role only, RLS on, no policies; no foreign key to organization.
DO $$ BEGIN
  IF has_table_privilege('anon', 'public.workspace_deletions', 'SELECT') OR has_table_privilege('authenticated', 'public.workspace_deletions', 'SELECT')
     OR has_table_privilege('anon', 'public.workspace_deletions', 'INSERT') OR has_table_privilege('authenticated', 'public.workspace_deletions', 'INSERT')
     OR has_table_privilege('anon', 'public.workspace_deletions', 'UPDATE') OR has_table_privilege('authenticated', 'public.workspace_deletions', 'UPDATE')
     OR has_table_privilege('anon', 'public.workspace_deletions', 'DELETE') OR has_table_privilege('authenticated', 'public.workspace_deletions', 'DELETE') THEN
    RAISE EXCEPTION 'anon/authenticated still have privileges on workspace_deletions';
  END IF;
  IF NOT has_table_privilege('service_role', 'public.workspace_deletions', 'INSERT') THEN RAISE EXCEPTION 'service_role cannot insert'; END IF;
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.workspace_deletions'::regclass) THEN RAISE EXCEPTION 'RLS is off'; END IF;
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'workspace_deletions') THEN RAISE EXCEPTION 'a policy exists'; END IF;
  IF EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.workspace_deletions'::regclass AND contype = 'f') THEN
    RAISE EXCEPTION 'workspace_deletions has a foreign key';
  END IF;
END $$;

-- A browser key is refused.
SET ROLE anon;
DO $$ BEGIN
  BEGIN
    PERFORM count(*) FROM public.workspace_deletions;
    RAISE EXCEPTION 'anon read workspace_deletions';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SET ROLE authenticated;
DO $$ BEGIN
  BEGIN
    PERFORM count(*) FROM public.workspace_deletions;
    RAISE EXCEPTION 'authenticated read workspace_deletions';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    INSERT INTO public.workspace_deletions (organization_id, mode, requested_by, reason) VALUES ('org_a', 'delete', 'x', 'x');
    RAISE EXCEPTION 'authenticated wrote workspace_deletions';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;

-- Requests: defaults, the 24-hour delay, the checks on the request itself, one open request per organization.
DO $$
DECLARE d public.workspace_deletions%ROWTYPE;
        n integer;
BEGIN
  INSERT INTO public.workspace_deletions (organization_id, organization_name, mode, requested_by, reason, systems)
    VALUES ('org_a', 'Fixture A', 'archive', 'boss@example.com', 'test workspace', ARRAY['supabase', 'unipile', 'mobile'])
    RETURNING * INTO d;
  IF d.status <> 'pending' OR d.inventory <> '{}'::jsonb OR d.confirmed_at IS NOT NULL OR d.open_invoice_override
     OR d.purge_not_before <> d.requested_at + interval '24 hours' OR d.supabase_receipt IS NOT NULL THEN
    RAISE EXCEPTION 'bad request defaults: %', row_to_json(d);
  END IF;
  PERFORM pg_temp.refuses($q$INSERT INTO public.workspace_deletions (organization_id, mode, requested_by, reason)
    VALUES ('org_a', 'delete', 'boss@example.com', 'again')$q$, '23505', 'a second open request for an organization');
  PERFORM pg_temp.refuses($q$INSERT INTO public.workspace_deletions (organization_id, mode, requested_by, reason)
    VALUES ('org_b', 'wipe', 'boss@example.com', 'x')$q$, '23514', 'an unknown mode');
  PERFORM pg_temp.refuses($q$INSERT INTO public.workspace_deletions (organization_id, mode, requested_by, reason)
    VALUES ('org_b', 'delete', 'boss@example.com', '')$q$, '23514', 'an empty reason');
  PERFORM pg_temp.refuses($q$INSERT INTO public.workspace_deletions (organization_id, mode, requested_by, reason, purge_not_before)
    VALUES ('org_b', 'delete', 'boss@example.com', 'x', now() + interval '23 hours')$q$, '23514', 'a purge time under 24 hours');
  PERFORM pg_temp.refuses($q$INSERT INTO public.workspace_deletions (organization_id, mode, requested_by, reason, systems)
    VALUES ('org_b', 'delete', 'boss@example.com', 'x', ARRAY['supabase', 'dropbox'])$q$, '23514', 'an unknown part');
  PERFORM pg_temp.refuses($q$INSERT INTO public.workspace_deletions (organization_id, mode, requested_by, reason, open_invoice_override)
    VALUES ('org_b', 'delete', 'boss@example.com', 'x', true)$q$, '23514', 'an invoice override without its reason');
  PERFORM pg_temp.refuses($q$INSERT INTO public.workspace_deletions (organization_id, mode, requested_by, reason, inventory)
    VALUES ('org_b', 'delete', 'boss@example.com', 'x', '[]'::jsonb)$q$, '23514', 'an inventory that is not an object');
  PERFORM pg_temp.refuses(format($q$UPDATE public.workspace_deletions SET status = 'running' WHERE id = %L$q$, d.id),
    '23514', 'running without the confirmation');
  PERFORM pg_temp.refuses(format($q$UPDATE public.workspace_deletions SET status = 'cancelled' WHERE id = %L$q$, d.id),
    '23514', 'cancelled without who and when');
  PERFORM pg_temp.refuses(format($q$UPDATE public.workspace_deletions SET organization_id = NULL WHERE id = %L$q$, d.id),
    '23502', 'a request without an organization');

  -- Archive: confirmed, running; parts are claimed at once (no purge delay in archive mode).
  UPDATE public.workspace_deletions SET confirmed_at = now(), status = 'running',
    inventory = '{"supabase": {"tasks": 3}, "unipile": {"accounts": 1}}'::jsonb WHERE id = d.id;
  PERFORM pg_temp.refuses(format($q$UPDATE public.workspace_deletions SET pinecone_claimed_at = now(), pinecone_claimed_by = 'vector-api'
    WHERE id = %L$q$, d.id), '23514', 'a claim on a part that is not listed');
  PERFORM pg_temp.refuses(format($q$UPDATE public.workspace_deletions SET supabase_claimed_at = now() WHERE id = %L$q$, d.id),
    '23514', 'a claim without who');
  PERFORM pg_temp.refuses(format($q$UPDATE public.workspace_deletions SET unipile_receipt = '{"status": "done"}' WHERE id = %L$q$, d.id),
    '23514', 'a receipt without a claim');
  -- A claim as PostgREST makes it: only where the part is unclaimed. The second attempt changes nothing.
  UPDATE public.workspace_deletions SET supabase_claimed_at = now(), supabase_claimed_by = 'backoffice'
    WHERE id = d.id AND supabase_claimed_at IS NULL;
  UPDATE public.workspace_deletions SET supabase_claimed_at = now(), supabase_claimed_by = 'someone-else'
    WHERE id = d.id AND supabase_claimed_at IS NULL;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 0 OR (SELECT supabase_claimed_by FROM public.workspace_deletions WHERE id = d.id) <> 'backoffice' THEN
    RAISE EXCEPTION 'a claimed part was claimed again';
  END IF;
  PERFORM pg_temp.refuses(format($q$UPDATE public.workspace_deletions SET supabase_receipt = '[1]' WHERE id = %L$q$, d.id),
    '23514', 'a receipt that is not an object');
  PERFORM pg_temp.refuses(format($q$UPDATE public.workspace_deletions SET supabase_receipt = '{"rows": 3}' WHERE id = %L$q$, d.id),
    '23514', 'a receipt without a status');
  PERFORM pg_temp.refuses(format($q$UPDATE public.workspace_deletions SET supabase_receipt = '{"status": "ok"}' WHERE id = %L$q$, d.id),
    '23514', 'a receipt with an unknown status');
  UPDATE public.workspace_deletions SET supabase_receipt = '{"status": "done", "counts": {"tasks": 3}}' WHERE id = d.id;
  -- Two services write their own parts; neither overwrites the other.
  UPDATE public.workspace_deletions SET unipile_claimed_at = now(), unipile_claimed_by = 'backoffice',
    unipile_receipt = '{"status": "failed", "error": "timeout"}' WHERE id = d.id;
  UPDATE public.workspace_deletions SET mobile_claimed_at = now(), mobile_claimed_by = 'mobile-service',
    mobile_receipt = '{"status": "skipped", "note": "no phone rows"}' WHERE id = d.id;
  IF (SELECT supabase_receipt ->> 'status' FROM public.workspace_deletions WHERE id = d.id) <> 'done' THEN
    RAISE EXCEPTION 'a part overwrote another part''s receipt';
  END IF;
  PERFORM pg_temp.refuses(format($q$UPDATE public.workspace_deletions SET status = 'completed', completed_at = now() WHERE id = %L$q$, d.id),
    '23514', 'completed with a failed part');
  -- A failed part keeps the request open.
  UPDATE public.workspace_deletions SET status = 'failed' WHERE id = d.id;
  PERFORM pg_temp.refuses($q$INSERT INTO public.workspace_deletions (organization_id, mode, requested_by, reason)
    VALUES ('org_a', 'delete', 'boss@example.com', 'x')$q$, '23505', 'a new request while one has failed');
  -- A person re-runs the part: it is claimed again and done.
  UPDATE public.workspace_deletions SET status = 'running', unipile_claimed_at = now(), unipile_claimed_by = 'backoffice',
    unipile_receipt = '{"status": "done", "counts": {"accounts": 1}}' WHERE id = d.id;
  PERFORM pg_temp.refuses(format($q$UPDATE public.workspace_deletions SET status = 'completed' WHERE id = %L$q$, d.id),
    '23514', 'completed without the completion time');
  UPDATE public.workspace_deletions SET status = 'completed', completed_at = now() WHERE id = d.id;
  -- A completed archive is reversible; a new request for the organization is allowed once the old one is closed.
  PERFORM pg_temp.refuses(format($q$UPDATE public.workspace_deletions SET status = 'reversed' WHERE id = %L$q$, d.id),
    '23514', 'reversed without who and when');
  UPDATE public.workspace_deletions SET status = 'reversed', reversed_by = 'boss@example.com', reversed_at = now() WHERE id = d.id;
  INSERT INTO public.workspace_deletions (organization_id, mode, requested_by, reason, systems)
    VALUES ('org_a', 'delete', 'boss@example.com', 'second request', ARRAY['supabase'])
    RETURNING * INTO d;
  PERFORM pg_temp.refuses(format($q$UPDATE public.workspace_deletions SET status = 'reversed', reversed_by = 'x', reversed_at = now()
    WHERE id = %L$q$, d.id), '23514', 'a delete reversed');
  UPDATE public.workspace_deletions SET status = 'cancelled', cancelled_by = 'boss@example.com', cancelled_at = now() WHERE id = d.id;
  PERFORM pg_temp.refuses($q$INSERT INTO public.workspace_deletions (organization_id, mode, requested_by, reason, status, completed_at, confirmed_at)
    VALUES ('org_c', 'archive', 'boss@example.com', 'x', 'completed', now(), now())$q$, '23514', 'completed with no parts');
END $$;

-- Delete mode: no part is claimed before the purge time; the row is the receipt after the organization is gone.
DO $$
DECLARE v_early uuid; v_due uuid;
BEGIN
  INSERT INTO public.workspace_deletions (organization_id, organization_name, mode, requested_by, reason, systems, confirmed_at,
                                          status, open_invoice_override, override_reason)
    VALUES ('org_b', 'Fixture B', 'delete', 'boss@example.com', 'fake workspace', ARRAY['supabase', 'pinecone'], now(),
            'running', true, 'invoice voided by hand')
    RETURNING id INTO v_early;
  PERFORM pg_temp.refuses(format($q$UPDATE public.workspace_deletions SET supabase_claimed_at = now(), supabase_claimed_by = 'backoffice'
    WHERE id = %L$q$, v_early), '23514', 'a purge part claimed before the 24 hours');
  -- A request made two days ago is due.
  INSERT INTO public.workspace_deletions (organization_id, mode, requested_by, reason, systems, confirmed_at, status,
                                          requested_at, purge_not_before)
    VALUES ('org_c', 'delete', 'boss@example.com', 'fake workspace', ARRAY['supabase', 'pinecone', 'clerk'], now(), 'running',
            now() - interval '2 days', now() - interval '1 day')
    RETURNING id INTO v_due;
  UPDATE public.workspace_deletions SET supabase_claimed_at = now(), supabase_claimed_by = 'backoffice',
    supabase_receipt = '{"status": "done", "counts": {"organization": 1}}' WHERE id = v_due;
  UPDATE public.workspace_deletions SET pinecone_claimed_at = now(), pinecone_claimed_by = 'vector-api',
    pinecone_receipt = '{"status": "done", "counts": {"vectors": 120}}' WHERE id = v_due;
  PERFORM pg_temp.refuses(format($q$UPDATE public.workspace_deletions SET status = 'completed', completed_at = now() WHERE id = %L$q$, v_due),
    '23514', 'completed with a listed part still out');
  UPDATE public.workspace_deletions SET clerk_claimed_at = now(), clerk_claimed_by = 'backoffice',
    clerk_receipt = '{"status": "done"}' WHERE id = v_due;
  DELETE FROM public.organization WHERE id = 'org_c';
  UPDATE public.workspace_deletions SET status = 'completed', completed_at = now() WHERE id = v_due;
  IF (SELECT organization_id FROM public.workspace_deletions WHERE id = v_due) <> 'org_c' THEN
    RAISE EXCEPTION 'the receipt lost its organization';
  END IF;
  -- Deleting every organization leaves every receipt.
  DELETE FROM public.organization;
  IF (SELECT count(*) FROM public.workspace_deletions) <> 4 THEN RAISE EXCEPTION 'a receipt went with its organization'; END IF;

  -- updated_at moves on update (now() is fixed inside one transaction, so start from an old value).
  ALTER TABLE public.workspace_deletions DISABLE TRIGGER update_workspace_deletions_updated_at;
  UPDATE public.workspace_deletions SET updated_at = '2020-01-01' WHERE id = v_early;
  ALTER TABLE public.workspace_deletions ENABLE TRIGGER update_workspace_deletions_updated_at;
  UPDATE public.workspace_deletions SET inventory = '{"pinecone": {"vectors": 0}}' WHERE id = v_early;
  IF (SELECT updated_at FROM public.workspace_deletions WHERE id = v_early) < '2021-01-01' THEN RAISE EXCEPTION 'updated_at did not move'; END IF;
END $$;
SELECT 'backoffice cs agent deletion contract passed' AS result;
