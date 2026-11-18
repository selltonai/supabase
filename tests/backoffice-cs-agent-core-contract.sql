-- Migration 422's contract. Run by tests/run-backoffice-cs-agent-core-contract.sh on a disposable database.
DO $$
DECLARE
  t text;
  v_thread uuid;
  rec public.cs_recommendations%ROWTYPE;
  brief public.cs_briefs%ROWTYPE;
  n integer;
BEGIN
  -- Access: the service role only, RLS on, no policies.
  FOREACH t IN ARRAY ARRAY['cs_threads', 'cs_messages', 'cs_briefs', 'cs_recommendations', 'cs_costs'] LOOP
    IF has_table_privilege('anon', 'public.' || t, 'SELECT') OR has_table_privilege('authenticated', 'public.' || t, 'SELECT')
       OR has_table_privilege('anon', 'public.' || t, 'INSERT') OR has_table_privilege('authenticated', 'public.' || t, 'UPDATE') THEN
      RAISE EXCEPTION 'anon/authenticated still have privileges on %', t;
    END IF;
    IF NOT has_table_privilege('service_role', 'public.' || t, 'INSERT') THEN RAISE EXCEPTION 'service_role cannot insert into %', t; END IF;
    IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = ('public.' || t)::regclass) THEN RAISE EXCEPTION 'RLS is off on %', t; END IF;
    IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = t) THEN RAISE EXCEPTION '% has a policy', t; END IF;
  END LOOP;

  -- Threads and messages: a staff thread (no workspace) and a workspace thread; a message needs a known role.
  INSERT INTO public.cs_threads (staff_user) VALUES ('staff@example.com');
  INSERT INTO public.cs_threads (staff_user, organization_id, title) VALUES ('staff@example.com', 'org_a', 'About A') RETURNING id INTO v_thread;
  INSERT INTO public.cs_messages (thread_id, role, content) VALUES (v_thread, 'user', 'What is happening?');
  IF (SELECT m.trace FROM public.cs_messages m WHERE m.thread_id = v_thread LIMIT 1) <> '[]'::jsonb THEN RAISE EXCEPTION 'bad trace default'; END IF;
  BEGIN
    INSERT INTO public.cs_messages (thread_id, role) VALUES (v_thread, 'system');
    RAISE EXCEPTION 'an unknown role was accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.cs_threads (staff_user, organization_id) VALUES ('staff@example.com', 'org_unknown');
    RAISE EXCEPTION 'a thread for an unknown organization was accepted';
  EXCEPTION WHEN foreign_key_violation THEN NULL; END;

  -- Briefs: one row per day and scope; the scope key and the workspace must agree.
  INSERT INTO public.cs_briefs (day, scope_key) VALUES ('2026-11-11', 'global') RETURNING * INTO brief;
  IF brief.model_used OR brief.brief <> '{}'::jsonb OR brief.slack_posted_at IS NOT NULL THEN RAISE EXCEPTION 'bad brief defaults'; END IF;
  INSERT INTO public.cs_briefs (day, scope_key, organization_id, segment) VALUES ('2026-11-11', 'org_a', 'org_a', 'stalling');
  BEGIN
    INSERT INTO public.cs_briefs (day, scope_key) VALUES ('2026-11-11', 'global');
    RAISE EXCEPTION 'a second global brief for the day was accepted';
  EXCEPTION WHEN unique_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.cs_briefs (day, scope_key, organization_id) VALUES ('2026-11-12', 'global', 'org_a');
    RAISE EXCEPTION 'a global brief with a workspace was accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.cs_briefs (day, scope_key, organization_id) VALUES ('2026-11-12', 'org_b', 'org_a');
    RAISE EXCEPTION 'a brief whose scope key is another workspace was accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.cs_briefs (day, scope_key) VALUES ('2026-11-12', 'org_a');
    RAISE EXCEPTION 'a workspace brief without its workspace was accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;

  -- Recommendations: defaults, the approval guard, the status list, the single-proposal key.
  INSERT INTO public.cs_recommendations (organization_id, kind, thread_id, dedupe_key)
    VALUES ('org_a', 'email', v_thread, 'org_a:email:2026-W46') RETURNING * INTO rec;
  IF rec.status <> 'proposed' OR rec.created_by <> 'agent' OR rec.attempts <> 0 OR rec.payload <> '{}'::jsonb
     OR rec.grounding <> '{}'::jsonb OR rec.outcome <> '{}'::jsonb OR rec.approved_by IS NOT NULL THEN
    RAISE EXCEPTION 'bad recommendation defaults: %', row_to_json(rec);
  END IF;
  BEGIN
    UPDATE public.cs_recommendations SET status = 'approved' WHERE id = rec.id;
    RAISE EXCEPTION 'approved without an approver';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    UPDATE public.cs_recommendations SET status = 'executed', executed_at = now() WHERE id = rec.id;
    RAISE EXCEPTION 'executed without an approver';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    UPDATE public.cs_recommendations SET status = 'failed' WHERE id = rec.id;
    RAISE EXCEPTION 'failed without an approver';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    UPDATE public.cs_recommendations SET status = 'approved', approved_by = 'staff@example.com' WHERE id = rec.id;
    RAISE EXCEPTION 'approved without an approval time';
  EXCEPTION WHEN check_violation THEN NULL; END;
  UPDATE public.cs_recommendations SET status = 'approved', approved_by = 'staff@example.com', approved_at = now() WHERE id = rec.id;
  BEGIN
    UPDATE public.cs_recommendations SET status = 'executed' WHERE id = rec.id;
    RAISE EXCEPTION 'executed without an execution time';
  EXCEPTION WHEN check_violation THEN NULL; END;
  UPDATE public.cs_recommendations SET status = 'executed', executed_at = now() WHERE id = rec.id;
  -- Dismissing and expiring need no approver.
  INSERT INTO public.cs_recommendations (organization_id, kind, status, dismissed_by, dismissed_at)
    VALUES ('org_a', 'tip', 'dismissed', 'staff@example.com', now());
  INSERT INTO public.cs_recommendations (organization_id, kind, status) VALUES ('org_a', 'trial', 'expired');
  BEGIN
    INSERT INTO public.cs_recommendations (organization_id, kind, status) VALUES ('org_a', 'email', 'sent');
    RAISE EXCEPTION 'an unknown status was accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.cs_recommendations (organization_id, kind) VALUES ('org_a', '');
    RAISE EXCEPTION 'an empty kind was accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.cs_recommendations (organization_id, kind, dedupe_key) VALUES ('org_a', 'email', 'org_a:email:2026-W46');
    RAISE EXCEPTION 'a second proposal with the same key was accepted';
  EXCEPTION WHEN unique_violation THEN NULL; END;
  -- Without a key, any number of proposals is fine.
  INSERT INTO public.cs_recommendations (organization_id, kind) VALUES ('org_a', 'note'), ('org_a', 'note');
  BEGIN
    INSERT INTO public.cs_recommendations (organization_id, kind) VALUES ('org_unknown', 'email');
    RAISE EXCEPTION 'a proposal for an unknown organization was accepted';
  EXCEPTION WHEN foreign_key_violation THEN NULL; END;

  -- updated_at is set by the trigger on update (now() is fixed inside one transaction, so start from an old value).
  ALTER TABLE public.cs_recommendations DISABLE TRIGGER update_cs_recommendations_updated_at;
  UPDATE public.cs_recommendations SET updated_at = '2020-01-01' WHERE id = rec.id;
  ALTER TABLE public.cs_recommendations ENABLE TRIGGER update_cs_recommendations_updated_at;
  UPDATE public.cs_recommendations SET outcome = '{"replied": true}'::jsonb WHERE id = rec.id;
  IF (SELECT updated_at FROM public.cs_recommendations WHERE id = rec.id) < '2021-01-01' THEN RAISE EXCEPTION 'updated_at did not move'; END IF;

  -- Costs: defaults, no negative amounts, with and without a workspace.
  INSERT INTO public.cs_costs (task_kind, provider) VALUES ('brief', 'deepseek');
  INSERT INTO public.cs_costs (task_kind, provider, model, organization_id, input_tokens, output_tokens, usd)
    VALUES ('chat', 'deepseek', 'flash', 'org_b', 1200, 300, 0.000321);
  IF (SELECT usd FROM public.cs_costs WHERE organization_id = 'org_b') <> 0.000321 THEN RAISE EXCEPTION 'usd lost precision'; END IF;
  BEGIN
    INSERT INTO public.cs_costs (task_kind, provider, usd) VALUES ('chat', 'deepseek', -1);
    RAISE EXCEPTION 'a negative cost was accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;

  -- Deleting a workspace deletes its threads, messages, briefs and proposals; its costs stay, without the workspace.
  INSERT INTO public.cs_threads (staff_user, organization_id) VALUES ('staff@example.com', 'org_b') RETURNING id INTO v_thread;
  INSERT INTO public.cs_messages (thread_id, role, content) VALUES (v_thread, 'assistant', 'About B');
  INSERT INTO public.cs_briefs (day, scope_key, organization_id) VALUES ('2026-11-11', 'org_b', 'org_b');
  INSERT INTO public.cs_recommendations (organization_id, kind, thread_id) VALUES ('org_b', 'email', v_thread);
  DELETE FROM public.organization WHERE id = 'org_b';
  IF EXISTS (SELECT 1 FROM public.cs_threads WHERE organization_id = 'org_b')
     OR EXISTS (SELECT 1 FROM public.cs_messages m WHERE m.thread_id = v_thread)
     OR EXISTS (SELECT 1 FROM public.cs_briefs WHERE organization_id = 'org_b')
     OR EXISTS (SELECT 1 FROM public.cs_recommendations WHERE organization_id = 'org_b') THEN
    RAISE EXCEPTION 'cascade failed';
  END IF;
  SELECT count(*) INTO n FROM public.cs_costs WHERE task_kind = 'chat' AND organization_id IS NULL AND usd = 0.000321;
  IF n <> 1 THEN RAISE EXCEPTION 'the deleted workspace''s cost row did not stay'; END IF;
  -- Deleting a thread keeps its proposals, without the thread.
  DELETE FROM public.cs_threads WHERE id = rec.thread_id;
  IF (SELECT r.thread_id FROM public.cs_recommendations r WHERE r.id = rec.id) IS NOT NULL THEN RAISE EXCEPTION 'the proposal kept a deleted thread'; END IF;

  -- Lifecycle steps: the existing rows are untouched, the two new audiences and the filter are accepted.
  IF (SELECT count(*) FROM public.email_sequence_steps WHERE is_active AND signup_source IS NULL
        AND audience_mode IN ('not_activated', 'funnel_stage')) <> 2 THEN
    RAISE EXCEPTION 'an existing step changed';
  END IF;
  INSERT INTO public.email_sequence_steps (step_key, name, subject, body, audience_mode, signup_source)
    VALUES ('chase-stuck', 'Chase', 'Subject', 'Body', 'chase', 'web'),
           ('segment-phone', 'Segment', 'Subject', 'Body', 'segment', 'mobile');
  BEGIN
    INSERT INTO public.email_sequence_steps (step_key, name, subject, body, audience_mode) VALUES ('x', 'x', 'x', 'x', 'everyone');
    RAISE EXCEPTION 'an unknown audience was accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO public.email_sequence_steps (step_key, name, subject, body, signup_source) VALUES ('y', 'y', 'y', 'y', 'tablet');
    RAISE EXCEPTION 'an unknown signup source was accepted';
  EXCEPTION WHEN check_violation THEN NULL; END;
END $$;
SELECT 'backoffice cs agent core contract passed' AS result;
