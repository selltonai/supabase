-- KB gaps (448) contract. Runs after tests/fixtures/kb-gaps-bootstrap.sql and 448 applied twice.
-- Disposable database only. Every check raises on failure.

-- 1. Shape, access and idempotency ------------------------------------------------------------------

DO $$
DECLARE
  n integer;
BEGIN
  SELECT count(*) INTO n FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'kb_gaps';
  IF n <> 18 THEN RAISE EXCEPTION 'kb_gaps has % columns, expected 18', n; END IF;
  SELECT count(*) INTO n FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'kb_gap_events';
  IF n <> 6 THEN RAISE EXCEPTION 'kb_gap_events has % columns, expected 6', n; END IF;

  SELECT count(*) INTO n FROM pg_constraint
  WHERE conrelid = 'public.kb_gaps'::regclass AND conname = 'kb_gaps_org_kind_topic_key_key' AND contype = 'u';
  IF n <> 1 THEN RAISE EXCEPTION 'kb_gaps unique (organization_id, kind, topic_key): % constraints', n; END IF;
  SELECT count(*) INTO n FROM pg_constraint
  WHERE conrelid = 'public.kb_gap_events'::regclass AND conname = 'kb_gap_events_gap_source_key_key' AND contype = 'u';
  IF n <> 1 THEN RAISE EXCEPTION 'kb_gap_events unique (gap_id, source_key): % constraints', n; END IF;
  -- Applied twice: no duplicate unique constraints, triggers or indexes.
  SELECT count(*) INTO n FROM pg_constraint WHERE conrelid = 'public.kb_gaps'::regclass AND contype = 'u';
  IF n <> 1 THEN RAISE EXCEPTION 'kb_gaps has % unique constraints after two runs, expected 1', n; END IF;
  SELECT count(*) INTO n FROM pg_constraint WHERE conrelid = 'public.kb_gap_events'::regclass AND contype = 'u';
  IF n <> 1 THEN RAISE EXCEPTION 'kb_gap_events has % unique constraints after two runs, expected 1', n; END IF;
  SELECT count(*) INTO n FROM pg_trigger WHERE tgrelid = 'public.kb_gaps'::regclass AND NOT tgisinternal;
  IF n <> 1 THEN RAISE EXCEPTION 'kb_gaps has % triggers, expected 1 (updated_at)', n; END IF;

  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.kb_gaps'::regclass) THEN
    RAISE EXCEPTION 'RLS is off on kb_gaps';
  END IF;
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.kb_gap_events'::regclass) THEN
    RAISE EXCEPTION 'RLS is off on kb_gap_events';
  END IF;
  SELECT count(*) INTO n FROM pg_policies WHERE schemaname = 'public' AND tablename IN ('kb_gaps', 'kb_gap_events');
  IF n <> 0 THEN RAISE EXCEPTION 'kb gaps tables have % policies, expected none', n; END IF;

  -- Service role only.
  IF has_table_privilege('anon', 'public.kb_gaps', 'SELECT')
     OR has_table_privilege('authenticated', 'public.kb_gaps', 'SELECT')
     OR has_table_privilege('anon', 'public.kb_gap_events', 'SELECT')
     OR has_table_privilege('authenticated', 'public.kb_gap_events', 'SELECT')
     OR has_table_privilege('anon', 'public.kb_gaps', 'INSERT')
     OR has_table_privilege('authenticated', 'public.kb_gaps', 'UPDATE')
     OR has_table_privilege('authenticated', 'public.kb_gap_events', 'INSERT') THEN
    RAISE EXCEPTION 'anon or authenticated holds a privilege on the kb gaps tables';
  END IF;
  IF NOT has_table_privilege('service_role', 'public.kb_gaps', 'SELECT')
     OR NOT has_table_privilege('service_role', 'public.kb_gap_events', 'SELECT') THEN
    RAISE EXCEPTION 'service_role cannot read the kb gaps tables';
  END IF;
  IF has_function_privilege('anon', 'public.record_kb_gap(text, uuid, text, text, text, text, text, text, uuid, text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.record_kb_gap(text, uuid, text, text, text, text, text, text, uuid, text)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.set_kb_gap_status(text, uuid, text, uuid, text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.set_kb_gap_status(text, uuid, text, uuid, text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'anon or authenticated can execute a kb gaps function';
  END IF;
  IF NOT has_function_privilege('service_role', 'public.record_kb_gap(text, uuid, text, text, text, text, text, text, uuid, text)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.set_kb_gap_status(text, uuid, text, uuid, text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'service_role cannot execute a kb gaps function';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_proc
    WHERE oid IN ('public.record_kb_gap(text, uuid, text, text, text, text, text, text, uuid, text)'::regprocedure,
                  'public.set_kb_gap_status(text, uuid, text, uuid, text)'::regprocedure)
      AND (NOT prosecdef OR NOT (proconfig @> ARRAY['search_path=public, pg_temp']))
  ) THEN
    RAISE EXCEPTION 'a kb gaps function is not SECURITY DEFINER with search_path = public, pg_temp';
  END IF;
END $$;

-- The browser keys are refused for real, not only on paper.
SET LOCAL ROLE anon;
DO $$
BEGIN
  BEGIN
    PERFORM 1 FROM public.kb_gaps;
    RAISE EXCEPTION 'anon could select kb_gaps';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM public.record_kb_gap('org_a', NULL, 'question', NULL, 'x', 'x', NULL, 'email', NULL, 'email:anon');
    RAISE EXCEPTION 'anon could execute record_kb_gap';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;
RESET ROLE;
SET LOCAL ROLE authenticated;
DO $$
BEGIN
  BEGIN
    PERFORM 1 FROM public.kb_gap_events;
    RAISE EXCEPTION 'authenticated could select kb_gap_events';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM public.set_kb_gap_status('org_a', gen_random_uuid(), 'open', NULL, 'user_x');
    RAISE EXCEPTION 'authenticated could execute set_kb_gap_status';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END $$;
RESET ROLE;

-- 2. Counting ---------------------------------------------------------------------------------------

SET LOCAL ROLE service_role;
DO $$
DECLARE
  r jsonb;
  r2 jsonb;
  g public.kb_gaps;
  n integer;
BEGIN
  r := public.record_kb_gap('org_a', '11111111-1111-1111-1111-111111111111', 'objection', 'pricing', 'price-too-high',
                            'Price too high for a small team', 'We are only five people, this is too expensive.',
                            'email', '99999999-9999-9999-9999-999999999991', 'email:e1');
  IF (r->>'counted')::boolean IS NOT TRUE OR r->>'gap_id' IS NULL THEN
    RAISE EXCEPTION 'first source not counted: %', r;
  END IF;
  SELECT * INTO g FROM public.kb_gaps WHERE id = (r->>'gap_id')::uuid;
  IF g.occurrences <> 1 OR g.status <> 'open' OR g.last_seen_at IS NULL OR g.first_seen_at IS NULL
     OR g.objection_type <> 'pricing' OR g.channel <> 'email' OR g.organization_id <> 'org_a' THEN
    RAISE EXCEPTION 'first gap row wrong: %', row_to_json(g);
  END IF;

  -- The same source again (a replayed webhook): same gap, not counted.
  r2 := public.record_kb_gap('org_a', '11111111-1111-1111-1111-111111111111', 'objection', 'pricing', 'price-too-high',
                             'Price too high for a small team', 'We are only five people, this is too expensive.',
                             'email', '99999999-9999-9999-9999-999999999991', 'email:e1');
  IF (r2->>'counted')::boolean IS NOT FALSE OR r2->>'gap_id' <> r->>'gap_id' THEN
    RAISE EXCEPTION 'same source counted twice or another gap: %', r2;
  END IF;
  SELECT occurrences INTO n FROM public.kb_gaps WHERE id = (r->>'gap_id')::uuid;
  IF n <> 1 THEN RAISE EXCEPTION 'same source twice: occurrences %, expected 1', n; END IF;
  SELECT count(*) INTO n FROM public.kb_gap_events WHERE gap_id = (r->>'gap_id')::uuid;
  IF n <> 1 THEN RAISE EXCEPTION 'same source twice: % events, expected 1', n; END IF;

  -- A second source (LinkedIn, latest texts win; a null example keeps the last one).
  r2 := public.record_kb_gap('org_a', NULL, 'objection', 'pricing', 'price-too-high',
                             'Pricing too high', NULL, 'linkedin', '99999999-9999-9999-9999-999999999992',
                             'linkedin:m1');
  IF (r2->>'counted')::boolean IS NOT TRUE OR r2->>'gap_id' <> r->>'gap_id' THEN
    RAISE EXCEPTION 'second source not counted on the same gap: %', r2;
  END IF;
  SELECT * INTO g FROM public.kb_gaps WHERE id = (r->>'gap_id')::uuid;
  IF g.occurrences <> 2 OR g.topic <> 'Pricing too high' OR g.channel <> 'linkedin'
     OR g.example_text <> 'We are only five people, this is too expensive.'
     OR g.last_contact_id <> '99999999-9999-9999-9999-999999999992' THEN
    RAISE EXCEPTION 'two sources: gap row wrong: %', row_to_json(g);
  END IF;

  -- The same source key on another gap counts there (uniqueness is per gap).
  r2 := public.record_kb_gap('org_a', NULL, 'question', NULL, 'price-too-high', 'Do you have a price list?', NULL,
                             'email', NULL, 'email:e1');
  IF (r2->>'counted')::boolean IS NOT TRUE OR r2->>'gap_id' = r->>'gap_id' THEN
    RAISE EXCEPTION 'a question with the same topic_key must be its own gap: %', r2;
  END IF;

  -- Another workspace with the same topic: its own gap. A play of another workspace is not linked.
  r2 := public.record_kb_gap('org_b', '11111111-1111-1111-1111-111111111111', 'objection', 'pricing', 'price-too-high',
                             'Too expensive', NULL, 'email', NULL, 'email:e1');
  IF (r2->>'counted')::boolean IS NOT TRUE OR r2->>'gap_id' = r->>'gap_id' THEN
    RAISE EXCEPTION 'org_b must get its own gap: %', r2;
  END IF;
  IF (SELECT campaign_id FROM public.kb_gap_events WHERE gap_id = (r2->>'gap_id')::uuid) IS NOT NULL THEN
    RAISE EXCEPTION 'a play of another workspace was linked to an event';
  END IF;
  IF (SELECT campaign_id FROM public.kb_gap_events WHERE gap_id = (r->>'gap_id')::uuid AND source_key = 'email:e1')
     IS DISTINCT FROM '11111111-1111-1111-1111-111111111111'::uuid THEN
    RAISE EXCEPTION 'the play of the same workspace was not linked';
  END IF;

  -- Long texts are cut, not refused.
  r2 := public.record_kb_gap('org_a', NULL, 'question', NULL, 'long', repeat('t', 500), repeat('e', 900),
                             'email', NULL, 'email:long');
  SELECT * INTO g FROM public.kb_gaps WHERE id = (r2->>'gap_id')::uuid;
  IF char_length(g.topic) <> 120 OR char_length(g.example_text) <> 300 THEN
    RAISE EXCEPTION 'texts not cut to 120 / 300: % / %', char_length(g.topic), char_length(g.example_text);
  END IF;
END $$;

-- 3. Status: answered reopens, dismissed stays and counts -------------------------------------------

DO $$
DECLARE
  v_gap uuid;
  r jsonb;
  g public.kb_gaps;
  v_before timestamptz;
BEGIN
  SELECT id INTO v_gap FROM public.kb_gaps WHERE organization_id = 'org_a' AND kind = 'objection' AND topic_key = 'price-too-high';

  r := public.set_kb_gap_status('org_a', v_gap, 'answered', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'user_1');
  IF r <> jsonb_build_object('gap_id', v_gap, 'status', 'answered') THEN
    RAISE EXCEPTION 'set_kb_gap_status answered returned %', r;
  END IF;
  SELECT * INTO g FROM public.kb_gaps WHERE id = v_gap;
  IF g.status <> 'answered' OR g.answered_file_id <> 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
     OR g.status_changed_by <> 'user_1' OR g.status_changed_at IS NULL THEN
    RAISE EXCEPTION 'answered gap row wrong: %', row_to_json(g);
  END IF;

  -- The same source again does not reopen it.
  r := public.record_kb_gap('org_a', NULL, 'objection', 'pricing', 'price-too-high', 'Pricing too high', NULL,
                            'linkedin', NULL, 'linkedin:m1');
  IF (r->>'counted')::boolean IS NOT FALSE OR (SELECT status FROM public.kb_gaps WHERE id = v_gap) <> 'answered' THEN
    RAISE EXCEPTION 'a replayed source reopened an answered gap: %', r;
  END IF;

  -- A new source reopens it and keeps the answer's file.
  r := public.record_kb_gap('org_a', NULL, 'objection', 'pricing', 'price-too-high', 'Pricing too high', NULL,
                            'email', NULL, 'email:e2');
  SELECT * INTO g FROM public.kb_gaps WHERE id = v_gap;
  IF (r->>'counted')::boolean IS NOT TRUE OR g.status <> 'open' OR g.occurrences <> 3
     OR g.answered_file_id IS DISTINCT FROM 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid
     OR g.status_changed_by <> 'system' THEN
    RAISE EXCEPTION 'answered gap seen again: %', row_to_json(g);
  END IF;

  -- Dismissed stays dismissed and still counts.
  r := public.set_kb_gap_status('org_a', v_gap, 'dismissed', NULL, 'user_2');
  IF r->>'status' <> 'dismissed' THEN RAISE EXCEPTION 'dismiss returned %', r; END IF;
  SELECT status_changed_at INTO v_before FROM public.kb_gaps WHERE id = v_gap;
  r := public.record_kb_gap('org_a', NULL, 'objection', 'pricing', 'price-too-high', 'Pricing too high', NULL,
                            'email', NULL, 'email:e3');
  SELECT * INTO g FROM public.kb_gaps WHERE id = v_gap;
  IF (r->>'counted')::boolean IS NOT TRUE OR g.status <> 'dismissed' OR g.occurrences <> 4
     OR g.status_changed_by <> 'user_2' OR g.status_changed_at <> v_before THEN
    RAISE EXCEPTION 'dismissed gap seen again: %', row_to_json(g);
  END IF;

  -- Back to open by hand.
  r := public.set_kb_gap_status('org_a', v_gap, 'open', NULL, 'user_3');
  IF r <> jsonb_build_object('gap_id', v_gap, 'status', 'open')
     OR (SELECT status FROM public.kb_gaps WHERE id = v_gap) <> 'open' THEN
    RAISE EXCEPTION 'reopen by hand returned %', r;
  END IF;

  -- Another workspace's gap, or none: not_found, and nothing changes.
  r := public.set_kb_gap_status('org_b', v_gap, 'dismissed', NULL, 'intruder');
  IF r <> jsonb_build_object('error', 'not_found') THEN
    RAISE EXCEPTION 'another workspace''s gap: %', r;
  END IF;
  IF (SELECT status FROM public.kb_gaps WHERE id = v_gap) <> 'open' THEN
    RAISE EXCEPTION 'another workspace changed the gap';
  END IF;
  r := public.set_kb_gap_status('org_a', gen_random_uuid(), 'dismissed', NULL, 'user_3');
  IF r <> jsonb_build_object('error', 'not_found') THEN
    RAISE EXCEPTION 'a missing gap: %', r;
  END IF;

  -- Another workspace's file is refused as the answer.
  BEGIN
    PERFORM public.set_kb_gap_status('org_a', v_gap, 'answered', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'user_3');
    RAISE EXCEPTION 'another workspace''s file was accepted as the answer';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
  -- A bad status is refused.
  BEGIN
    PERFORM public.set_kb_gap_status('org_a', v_gap, 'closed', NULL, 'user_3');
    RAISE EXCEPTION 'status closed was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
END $$;

-- 4. Bad input is refused ---------------------------------------------------------------------------

DO $$
BEGIN
  BEGIN
    PERFORM public.record_kb_gap('org_a', NULL, 'complaint', NULL, 'k', 't', NULL, 'email', NULL, 'email:bad1');
    RAISE EXCEPTION 'kind complaint was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
  BEGIN
    PERFORM public.record_kb_gap('org_a', NULL, 'question', NULL, 'k', 't', NULL, 'sms', NULL, 'email:bad2');
    RAISE EXCEPTION 'channel sms was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
  BEGIN
    PERFORM public.record_kb_gap('org_a', NULL, 'objection', 'budget', 'k', 't', NULL, 'email', NULL, 'email:bad3');
    RAISE EXCEPTION 'objection_type budget was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
  BEGIN
    PERFORM public.record_kb_gap('org_a', NULL, 'question', NULL, '  ', 't', NULL, 'email', NULL, 'email:bad4');
    RAISE EXCEPTION 'an empty topic_key was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
  BEGIN
    PERFORM public.record_kb_gap('org_a', NULL, 'question', NULL, 'k', 't', NULL, 'email', NULL, NULL);
    RAISE EXCEPTION 'a missing source_key was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
  IF EXISTS (SELECT 1 FROM public.kb_gaps WHERE topic_key = 'k') THEN
    RAISE EXCEPTION 'a refused call left a gap behind';
  END IF;

  -- The table's own CHECKs and uniques hold for a direct write too.
  BEGIN
    INSERT INTO public.kb_gaps (organization_id, kind, topic_key, topic, channel) VALUES ('org_a', 'complaint', 'd1', 't', 'email');
    RAISE EXCEPTION 'CHECK on kind did not hold';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  BEGIN
    INSERT INTO public.kb_gaps (organization_id, kind, topic_key, topic, channel) VALUES ('org_a', 'question', 'd2', 't', 'sms');
    RAISE EXCEPTION 'CHECK on channel did not hold';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  BEGIN
    INSERT INTO public.kb_gaps (organization_id, kind, objection_type, topic_key, topic, channel)
    VALUES ('org_a', 'objection', 'budget', 'd3', 't', 'email');
    RAISE EXCEPTION 'CHECK on objection_type did not hold';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  BEGIN
    INSERT INTO public.kb_gaps (organization_id, kind, topic_key, topic, channel, status)
    VALUES ('org_a', 'question', 'd4', 't', 'email', 'closed');
    RAISE EXCEPTION 'CHECK on status did not hold';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  BEGIN
    INSERT INTO public.kb_gaps (organization_id, kind, topic_key, topic, channel)
    VALUES ('org_a', 'question', 'd5', repeat('t', 121), 'email');
    RAISE EXCEPTION 'CHECK on topic length did not hold';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  BEGIN
    INSERT INTO public.kb_gaps (organization_id, kind, topic_key, topic, example_text, channel)
    VALUES ('org_a', 'question', 'd6', 't', repeat('e', 301), 'email');
    RAISE EXCEPTION 'CHECK on example_text length did not hold';
  EXCEPTION WHEN check_violation THEN NULL;
  END;
  BEGIN
    INSERT INTO public.kb_gaps (organization_id, kind, topic_key, topic, channel)
    VALUES ('org_a', 'objection', 'price-too-high', 't', 'email');
    RAISE EXCEPTION 'UNIQUE (organization_id, kind, topic_key) did not hold';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
  BEGIN
    INSERT INTO public.kb_gap_events (gap_id, organization_id, source_key)
    SELECT id, organization_id, 'email:e1' FROM public.kb_gaps
    WHERE organization_id = 'org_a' AND kind = 'objection' AND topic_key = 'price-too-high';
    RAISE EXCEPTION 'UNIQUE (gap_id, source_key) did not hold';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
END $$;
RESET ROLE;

-- 5. Deletes: file -> answered_file_id NULL, play -> event campaign_id NULL, gap -> events, workspace -> gaps ------

DO $$
DECLARE
  r jsonb;
  v_gap uuid;
  n integer;
BEGIN
  r := public.record_kb_gap('org_a', '11111111-1111-1111-1111-111111111111', 'question', NULL, 'integrations',
                            'Do you integrate with HubSpot?', NULL, 'email', NULL, 'email:del1');
  v_gap := (r->>'gap_id')::uuid;
  PERFORM public.set_kb_gap_status('org_a', v_gap, 'answered', 'cccccccc-cccc-cccc-cccc-cccccccccccc', 'user_1');
  DELETE FROM public.organization_files WHERE id = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
  IF (SELECT answered_file_id FROM public.kb_gaps WHERE id = v_gap) IS NOT NULL THEN
    RAISE EXCEPTION 'deleting the answer file did not clear answered_file_id';
  END IF;
  IF (SELECT status FROM public.kb_gaps WHERE id = v_gap) <> 'answered' THEN
    RAISE EXCEPTION 'deleting the answer file changed the status';
  END IF;

  DELETE FROM public.campaigns WHERE id = '11111111-1111-1111-1111-111111111111';
  IF EXISTS (SELECT 1 FROM public.kb_gap_events WHERE campaign_id IS NOT NULL) THEN
    RAISE EXCEPTION 'deleting the play did not clear the events'' campaign_id';
  END IF;
  SELECT count(*) INTO n FROM public.kb_gap_events WHERE gap_id = v_gap;
  IF n <> 1 THEN RAISE EXCEPTION 'deleting the play removed events (% left)', n; END IF;

  DELETE FROM public.kb_gaps WHERE id = v_gap;
  IF EXISTS (SELECT 1 FROM public.kb_gap_events WHERE gap_id = v_gap) THEN
    RAISE EXCEPTION 'deleting a gap left its events';
  END IF;

  PERFORM public.record_kb_gap('org_gone', NULL, 'question', NULL, 'q', 'Question', NULL, 'linkedin', NULL, 'linkedin:g1');
  DELETE FROM public.organization WHERE id = 'org_gone';
  IF EXISTS (SELECT 1 FROM public.kb_gaps WHERE organization_id = 'org_gone')
     OR EXISTS (SELECT 1 FROM public.kb_gap_events WHERE organization_id = 'org_gone') THEN
    RAISE EXCEPTION 'deleting a workspace left its gaps or events';
  END IF;
END $$;

\echo 'kb gaps contract: all checks passed'
