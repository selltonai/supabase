-- ============================================================
-- Migration: 448_kb-gaps
-- Date:      2026-11-20
-- Purpose:   Missing answers back to the user (PLAN_OBJECTIONS_KB_GAPS_2026-11-20.md section 5, S1): a reply asks
--            a question or raises an objection the workspace's knowledge base cannot answer; the engine records it
--            as a gap so the user can add the answer.
--            1. kb_gaps: one row per workspace, kind and topic_key. occurrences counts the distinct replies that
--               raised it. status open / answered / dismissed; an answered gap seen again goes back to open
--               (keeping answered_file_id: the answer did not help, so it must show); a dismissed gap stays
--               dismissed but still counts.
--            2. kb_gap_events: one row per gap and source (email:<email_id> or linkedin:<message_id>). The unique
--               (gap_id, source_key) makes a replayed webhook or a retried task count once.
--            3. record_kb_gap: the engine's only writer (upsert gap, insert event, count only a new event).
--            4. set_kb_gap_status: the app's status change (open, answered with the answer's file, dismissed).
--            Data minimisation: a short gap text (topic <= 120, example_text <= 300 characters) and ids, never
--            email bodies.
-- Projects:  selltonai-database/supabase (owner); selltonai-modal (writer via record_kb_gap);
--            selltonai app (reader via server routes, set_kb_gap_status).
-- Contract:  PLAN_OBJECTIONS_KB_GAPS_2026-11-20 section 4.3. Additive only. Service role only: RLS on with no
--            policies, anon and authenticated hold no privileges on the tables or the functions.
--            Merge order: this, then Modal, then the app. Each tolerates the next being absent.
-- Depends:   public.organization, public.campaigns, public.organization_files,
--            public.update_updated_at_column() (release_1.0.0; last re-declared by 300).
-- Rollback:  rollback/448_kb-gaps.rollback.sql
-- ============================================================

SET LOCAL lock_timeout = '10s';

-- 1. The gap ---------------------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.kb_gaps (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  kind text NOT NULL CONSTRAINT kb_gaps_kind_check CHECK (kind IN ('question', 'objection')),
  objection_type text CONSTRAINT kb_gaps_objection_type_check
    CHECK (objection_type IN ('pricing', 'timing', 'fit', 'competitor', 'already_solved', 'other')),
  topic_key text NOT NULL,
  topic text NOT NULL CONSTRAINT kb_gaps_topic_length_check CHECK (char_length(topic) <= 120),
  example_text text CONSTRAINT kb_gaps_example_text_length_check CHECK (char_length(example_text) <= 300),
  channel text NOT NULL CONSTRAINT kb_gaps_channel_check CHECK (channel IN ('email', 'linkedin')),
  occurrences integer NOT NULL DEFAULT 0,
  first_seen_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz,
  last_contact_id uuid,
  status text NOT NULL DEFAULT 'open' CONSTRAINT kb_gaps_status_check CHECK (status IN ('open', 'answered', 'dismissed')),
  answered_file_id uuid REFERENCES public.organization_files(id) ON DELETE SET NULL,
  status_changed_at timestamptz,
  status_changed_by text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.kb_gaps'::regclass AND conname = 'kb_gaps_org_kind_topic_key_key'
  ) THEN
    ALTER TABLE public.kb_gaps
      ADD CONSTRAINT kb_gaps_org_kind_topic_key_key UNIQUE (organization_id, kind, topic_key);
  END IF;
END $$;

COMMENT ON TABLE public.kb_gaps IS
  'A question or objection from a reply that the workspace''s knowledge base could not answer (448). One row per organization_id, kind and topic_key; topic and example_text are short texts (<= 120 and <= 300 characters), never an email body. occurrences counts distinct sources (kb_gap_events). Written only through record_kb_gap (engine) and set_kb_gap_status (app). An answered gap seen again goes back to open and keeps answered_file_id; a dismissed gap stays dismissed and still counts. status_changed_by is the Clerk user id, or system for a reopen.';

CREATE INDEX IF NOT EXISTS kb_gaps_org_status_occurrences_idx
  ON public.kb_gaps (organization_id, status, occurrences DESC);
-- For the ON DELETE SET NULL when a knowledge-base file is deleted.
CREATE INDEX IF NOT EXISTS kb_gaps_answered_file_idx
  ON public.kb_gaps (answered_file_id)
  WHERE answered_file_id IS NOT NULL;

DROP TRIGGER IF EXISTS update_kb_gaps_updated_at ON public.kb_gaps;
CREATE TRIGGER update_kb_gaps_updated_at
  BEFORE UPDATE ON public.kb_gaps
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

REVOKE ALL ON TABLE public.kb_gaps FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.kb_gaps TO service_role;
ALTER TABLE public.kb_gaps ENABLE ROW LEVEL SECURITY;
-- No policies on purpose: the service role (Modal, the app's server routes) reads and writes; browser keys see nothing.

-- 2. One source of a gap ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.kb_gap_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  gap_id uuid NOT NULL REFERENCES public.kb_gaps(id) ON DELETE CASCADE,
  organization_id text NOT NULL,
  campaign_id uuid REFERENCES public.campaigns(id) ON DELETE SET NULL,
  source_key text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.kb_gap_events'::regclass AND conname = 'kb_gap_events_gap_source_key_key'
  ) THEN
    ALTER TABLE public.kb_gap_events
      ADD CONSTRAINT kb_gap_events_gap_source_key_key UNIQUE (gap_id, source_key);
  END IF;
END $$;

COMMENT ON TABLE public.kb_gap_events IS
  'One source of a kb_gaps row (448): source_key is email:<email_id> or linkedin:<message_id>, never a task id. The unique (gap_id, source_key) makes a gap count once per source. Deleted with its gap; campaign_id becomes NULL when the play is deleted.';

-- Events by gap: the unique constraint's index (gap_id, source_key) serves it.
-- For the ON DELETE SET NULL when a play is deleted.
CREATE INDEX IF NOT EXISTS kb_gap_events_campaign_idx
  ON public.kb_gap_events (campaign_id)
  WHERE campaign_id IS NOT NULL;

REVOKE ALL ON TABLE public.kb_gap_events FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.kb_gap_events TO service_role;
ALTER TABLE public.kb_gap_events ENABLE ROW LEVEL SECURITY;
-- No policies on purpose, as above.

-- 3. The engine's writer ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.record_kb_gap(
  p_org text,
  p_campaign uuid,
  p_kind text,
  p_objection_type text,
  p_topic_key text,
  p_topic text,
  p_example text,
  p_channel text,
  p_contact_id uuid,
  p_source_key text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_topic_key text := btrim(p_topic_key);
  v_source_key text := btrim(p_source_key);
  v_topic text := left(btrim(coalesce(nullif(btrim(p_topic), ''), p_topic_key)), 120);
  v_example text := left(nullif(btrim(p_example), ''), 300);
  v_campaign uuid;
  v_gap_id uuid;
  v_event_id uuid;
BEGIN
  IF p_org IS NULL OR btrim(p_org) = '' THEN
    RAISE EXCEPTION 'record_kb_gap: p_org is required' USING ERRCODE = '22023';
  END IF;
  IF p_kind IS NULL OR p_kind NOT IN ('question', 'objection') THEN
    RAISE EXCEPTION 'record_kb_gap: p_kind must be question or objection, got %', p_kind USING ERRCODE = '22023';
  END IF;
  IF p_objection_type IS NOT NULL
     AND p_objection_type NOT IN ('pricing', 'timing', 'fit', 'competitor', 'already_solved', 'other') THEN
    RAISE EXCEPTION 'record_kb_gap: unknown p_objection_type %', p_objection_type USING ERRCODE = '22023';
  END IF;
  IF p_channel IS NULL OR p_channel NOT IN ('email', 'linkedin') THEN
    RAISE EXCEPTION 'record_kb_gap: p_channel must be email or linkedin, got %', p_channel USING ERRCODE = '22023';
  END IF;
  IF v_topic_key IS NULL OR v_topic_key = '' THEN
    RAISE EXCEPTION 'record_kb_gap: p_topic_key is required' USING ERRCODE = '22023';
  END IF;
  IF v_source_key IS NULL OR v_source_key = '' THEN
    RAISE EXCEPTION 'record_kb_gap: p_source_key is required' USING ERRCODE = '22023';
  END IF;

  -- A play of another workspace (or one deleted meanwhile) is not linked.
  IF p_campaign IS NOT NULL THEN
    SELECT c.id INTO v_campaign
    FROM public.campaigns c
    WHERE c.id = p_campaign AND c.organization_id = p_org;
  END IF;

  -- One statement: creates the gap or takes its row lock, so concurrent calls for the same gap serialize here.
  INSERT INTO public.kb_gaps AS g
    (organization_id, kind, objection_type, topic_key, topic, example_text, channel, last_contact_id)
  VALUES
    (p_org, p_kind, p_objection_type, v_topic_key, v_topic, v_example, p_channel, p_contact_id)
  ON CONFLICT (organization_id, kind, topic_key) DO UPDATE
    SET topic = EXCLUDED.topic,
        example_text = coalesce(EXCLUDED.example_text, g.example_text),
        objection_type = coalesce(EXCLUDED.objection_type, g.objection_type),
        channel = EXCLUDED.channel,
        last_contact_id = coalesce(EXCLUDED.last_contact_id, g.last_contact_id)
  RETURNING g.id INTO v_gap_id;

  INSERT INTO public.kb_gap_events (gap_id, organization_id, campaign_id, source_key)
  VALUES (v_gap_id, p_org, v_campaign, v_source_key)
  ON CONFLICT (gap_id, source_key) DO NOTHING
  RETURNING id INTO v_event_id;

  IF v_event_id IS NULL THEN
    RETURN jsonb_build_object('gap_id', v_gap_id, 'counted', false);
  END IF;

  UPDATE public.kb_gaps g
  SET occurrences = g.occurrences + 1,
      last_seen_at = now(),
      status = CASE WHEN g.status = 'answered' THEN 'open' ELSE g.status END,
      status_changed_at = CASE WHEN g.status = 'answered' THEN now() ELSE g.status_changed_at END,
      status_changed_by = CASE WHEN g.status = 'answered' THEN 'system' ELSE g.status_changed_by END
  WHERE g.id = v_gap_id;

  RETURN jsonb_build_object('gap_id', v_gap_id, 'counted', true);
END;
$$;

COMMENT ON FUNCTION public.record_kb_gap(text, uuid, text, text, text, text, text, text, uuid, text) IS
  'Records a knowledge-base gap from a reply (448). Upserts kb_gaps on (organization_id, kind, topic_key) with the latest topic, example, objection type, channel and contact; inserts the kb_gap_events row for p_source_key (email:<email_id> or linkedin:<message_id>). Only a new source counts: occurrences + 1, last_seen_at, and an answered gap goes back to open (answered_file_id kept, status_changed_by system); a dismissed gap stays dismissed. topic and example are cut to 120 and 300 characters. Returns {gap_id, counted}.';

REVOKE ALL ON FUNCTION public.record_kb_gap(text, uuid, text, text, text, text, text, text, uuid, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_kb_gap(text, uuid, text, text, text, text, text, text, uuid, text)
  TO service_role;

-- 4. The app's status change -----------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.set_kb_gap_status(
  p_org text,
  p_gap_id uuid,
  p_status text,
  p_file_id uuid,
  p_actor text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_gap_id uuid;
BEGIN
  IF p_status IS NULL OR p_status NOT IN ('open', 'answered', 'dismissed') THEN
    RAISE EXCEPTION 'set_kb_gap_status: p_status must be open, answered or dismissed, got %', p_status
      USING ERRCODE = '22023';
  END IF;
  -- The answer must be a file of the same workspace.
  IF p_status = 'answered' AND p_file_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.organization_files f WHERE f.id = p_file_id AND f.organization_id = p_org
  ) THEN
    RAISE EXCEPTION 'set_kb_gap_status: file % is not a file of this workspace', p_file_id USING ERRCODE = '22023';
  END IF;

  UPDATE public.kb_gaps g
  SET status = p_status,
      answered_file_id = CASE WHEN p_status = 'answered' THEN p_file_id ELSE g.answered_file_id END,
      status_changed_at = now(),
      status_changed_by = p_actor
  WHERE g.id = p_gap_id AND g.organization_id = p_org
  RETURNING g.id INTO v_gap_id;

  IF v_gap_id IS NULL THEN
    RETURN jsonb_build_object('error', 'not_found');
  END IF;
  RETURN jsonb_build_object('gap_id', v_gap_id, 'status', p_status);
END;
$$;

COMMENT ON FUNCTION public.set_kb_gap_status(text, uuid, text, uuid, text) IS
  'The app''s status change for a kb_gaps row of p_org (448): open, answered (answered_file_id = p_file_id, a file of the same workspace) or dismissed; sets status_changed_at and status_changed_by (the Clerk user id). Returns {gap_id, status}, or {error: not_found} for a gap of another workspace or none.';

REVOKE ALL ON FUNCTION public.set_kb_gap_status(text, uuid, text, uuid, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.set_kb_gap_status(text, uuid, text, uuid, text) TO service_role;

-- Verify:
-- select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'kb_gaps';
--   -> 18
-- select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'kb_gap_events';
--   -> 6
-- select relrowsecurity from pg_class where oid in ('public.kb_gaps'::regclass, 'public.kb_gap_events'::regclass);
--   -> t, t
-- select has_function_privilege('authenticated', 'public.record_kb_gap(text, uuid, text, text, text, text, text, text, uuid, text)', 'EXECUTE'),
--        has_function_privilege('authenticated', 'public.set_kb_gap_status(text, uuid, text, uuid, text)', 'EXECUTE');
--   -> f, f
