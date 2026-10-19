-- ============================================================
-- Migration: 405_bump-verification-digest (next-release; the same bytes on main and stage)
-- Date:      2026-10-19
-- Purpose:   KAN-309 V2 (Milka 2026-10-19). Company and contact verification notify ONCE per campaign per day per
--            person, updated in place, instead of once per task (prod since 10-01: 88% of 5,030 notifications were
--            task_assigned, ~97% of those Company Verification; one user got 549 in a week).
-- Projects:  Caller: selltonai-modal task_service (service role), instead of notify_task_created per verification
--            task, and only when Autonomous did not already handle the task. The caller resolves the recipient
--            (recipient rules unchanged) and checks the person's in-app preference: this function does not.
--            Reader: the bell (selltonai /api/notifications), unchanged; the row is an ordinary notification.
-- Contract:  public.bump_verification_digest(p_organization_id, p_user_id, p_campaign_id, p_kind, p_campaign_name,
--            p_action_url, p_delta DEFAULT 1) RETURNS uuid (the notification id).
--            dedup_key 'verification_digest:<kind>:<campaign_id>:<UTC date YYYY-MM-DD>'. One row per
--            (user_id, dedup_key) through migration 245's partial unique index idx_notifications_user_dedup_key, so the
--            ON CONFLICT names its predicate. type 'task_assigned' (in the type CHECK on both lines since 245; 353,
--            361 and 376 kept it), channels {in_app}, priority 'normal', entity ('campaign', campaign id),
--            metadata {kind:'verification_digest', verification_kind, campaign_id, count, organization_id}.
--            A bump adds p_delta to metadata.count, rewrites the title, and marks the row unread, undismissed and
--            created now, so it comes back to the top of the bell. Title: "<N> companies from <campaign> are ready to
--            verify" ("1 company ... is ready to verify"; contacts the same; no campaign name: "your campaign").
--            p_kind must be 'company' or 'contact', p_delta at least 1, and the three ids non-empty: anything else
--            raises 22023 (fail loud; the caller logs it).
-- Access:    SECURITY DEFINER, search_path public, every object schema-qualified. EXECUTE for service_role only
--            (revoked from PUBLIC, anon, authenticated; Supabase grants new functions to them by default). The title
--            helper is revoked from everyone; only the definer calls it.
-- Additive:  Two new functions. No table, column, index, CHECK or policy changes. Safe to drop: until Modal calls it,
--            nothing does. Rollback: rollback/405_bump-verification-digest.rollback.sql (deploy the Modal revert first).
-- ============================================================

CREATE OR REPLACE FUNCTION public.verification_digest_title(
  p_kind          text,
  p_count         integer,
  p_campaign_name text
) RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = public
AS $$
  SELECT p_count::text
    || CASE
         WHEN p_kind = 'contact' THEN CASE WHEN p_count = 1 THEN ' contact' ELSE ' contacts' END
         ELSE CASE WHEN p_count = 1 THEN ' company' ELSE ' companies' END
       END
    || ' from ' || COALESCE(NULLIF(btrim(p_campaign_name), ''), 'your campaign')
    || CASE WHEN p_count = 1 THEN ' is' ELSE ' are' END
    || ' ready to verify';
$$;

REVOKE ALL ON FUNCTION public.verification_digest_title(text, integer, text) FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION public.verification_digest_title(text, integer, text) IS
  'KAN-309 V2: the verification digest title, used by bump_verification_digest only.';

CREATE OR REPLACE FUNCTION public.bump_verification_digest(
  p_organization_id text,
  p_user_id         text,
  p_campaign_id     text,
  p_kind            text,
  p_campaign_name   text,
  p_action_url      text,
  p_delta           integer DEFAULT 1
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_dedup_key text;
  v_id uuid;
BEGIN
  IF COALESCE(btrim(p_organization_id), '') = '' OR COALESCE(btrim(p_user_id), '') = ''
     OR COALESCE(btrim(p_campaign_id), '') = '' THEN
    RAISE EXCEPTION 'bump_verification_digest: organization, user and campaign are required'
      USING ERRCODE = '22023';
  END IF;
  IF p_kind IS NULL OR p_kind NOT IN ('company', 'contact') THEN
    RAISE EXCEPTION 'bump_verification_digest: kind must be company or contact, got %', p_kind
      USING ERRCODE = '22023';
  END IF;
  IF p_delta IS NULL OR p_delta < 1 THEN
    RAISE EXCEPTION 'bump_verification_digest: delta must be at least 1, got %', p_delta
      USING ERRCODE = '22023';
  END IF;

  v_dedup_key := 'verification_digest:' || p_kind || ':' || p_campaign_id || ':'
    || to_char((now() AT TIME ZONE 'utc')::date, 'YYYY-MM-DD');

  INSERT INTO public.notifications AS n (
    organization_id, user_id, type, title, body, action_url, entity_type, entity_id,
    metadata, channels, priority, dedup_key
  ) VALUES (
    p_organization_id,
    p_user_id,
    'task_assigned',
    public.verification_digest_title(p_kind, p_delta, p_campaign_name),
    'Waiting for your review in Tasks.',
    p_action_url,
    'campaign',
    p_campaign_id,
    jsonb_build_object(
      'kind', 'verification_digest',
      'verification_kind', p_kind,
      'campaign_id', p_campaign_id,
      'count', p_delta,
      'organization_id', p_organization_id
    ),
    ARRAY['in_app']::text[],
    'normal',
    v_dedup_key
  )
  ON CONFLICT (user_id, dedup_key) WHERE dedup_key IS NOT NULL
  DO UPDATE SET
    title = public.verification_digest_title(
      p_kind,
      COALESCE(CASE WHEN n.metadata->>'count' ~ '^[0-9]{1,9}$' THEN (n.metadata->>'count')::integer END, 0) + p_delta,
      p_campaign_name
    ),
    body = 'Waiting for your review in Tasks.',
    metadata = n.metadata || jsonb_build_object(
      'kind', 'verification_digest',
      'verification_kind', p_kind,
      'campaign_id', p_campaign_id,
      'count', COALESCE(CASE WHEN n.metadata->>'count' ~ '^[0-9]{1,9}$' THEN (n.metadata->>'count')::integer END, 0) + p_delta,
      'organization_id', p_organization_id
    ),
    read = false,
    read_at = NULL,
    dismissed = false,
    created_at = now()
  RETURNING n.id INTO v_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.bump_verification_digest(text, text, text, text, text, text, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.bump_verification_digest(text, text, text, text, text, text, integer) TO service_role;

COMMENT ON FUNCTION public.bump_verification_digest(text, text, text, text, text, text, integer) IS
  'KAN-309 V2: one in-app "N companies/contacts from <campaign> are ready to verify" notification per person, campaign, kind and UTC day, counted up and resurfaced on every bump. Service role only; the caller resolves the recipient and the in-app preference.';

DO $$
BEGIN
  IF has_function_privilege('anon', 'public.bump_verification_digest(text, text, text, text, text, text, integer)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.bump_verification_digest(text, text, text, text, text, text, integer)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.verification_digest_title(text, integer, text)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.verification_digest_title(text, integer, text)', 'EXECUTE') THEN
    RAISE EXCEPTION '405: anon or authenticated can execute the verification digest functions';
  END IF;
  IF NOT has_function_privilege('service_role', 'public.bump_verification_digest(text, text, text, text, text, text, integer)', 'EXECUTE') THEN
    RAISE EXCEPTION '405: service_role cannot execute bump_verification_digest';
  END IF;
END $$;

-- Verify (read-only):
-- SELECT p.proname, p.prosecdef, pg_get_function_identity_arguments(p.oid) AS args,
--        has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_exec,              -- false
--        has_function_privilege('authenticated', p.oid, 'EXECUTE') AS user_exec,     -- false
--        has_function_privilege('service_role', p.oid, 'EXECUTE') AS service_exec    -- true for bump_verification_digest
--   FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
--  WHERE ns.nspname = 'public' AND p.proname IN ('bump_verification_digest', 'verification_digest_title');
-- After Modal ships: at most one row per person, campaign, kind and day.
-- SELECT user_id, dedup_key, count(*) FROM public.notifications
--  WHERE dedup_key LIKE 'verification_digest:%' GROUP BY 1, 2 HAVING count(*) > 1;   -- no rows
