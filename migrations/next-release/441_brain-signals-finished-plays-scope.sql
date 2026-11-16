-- ============================================================
-- Migration: 441_brain-signals-finished-plays-scope
-- Date:      2026-11-16
-- Purpose:   Brain signals keep watching the companies of finished plays (PLAN_SIGNALS_FINISHED_PLAYS_DRAFT_AND_JUDGE
--            _2026_11_16.md, part B, D2 to D5).
--            1. signal_scope_companies(organization_id): a fifth branch. A play that is paused, discovery_completed,
--               completed or fully_completed keeps its companies watched for 6 months after the play's last change
--               (campaigns.updated_at). Cancelled and draft plays do not. A company the gate blocked stays out, as in
--               the active play branch. The other four branches are as in 426.
--            2. The branch counts only for a workspace the Modal poll has stamped (a row
--               'finished_plays:<organization_id>' in brain_signal_cursor) and whose switch
--               general_settings.signals.finished_plays is not false (unset is on, D4). The poll writes the stamp only
--               after it has handled the companies this branch adds (part B, "no surprise read of past signals"):
--               with history_mode new_only it stamps them signals_history_skipped_at first; with history_mode all it
--               waits until the customer has confirmed the warning that counts them. So this migration alone, before
--               the Modal PR, widens no scope and causes no read: nothing writes the stamp yet.
--            3. signal_finished_play_companies(organization_id): the companies the branch adds that the scope does
--               not hold yet (finished-play companies minus signal_scope_companies), with the switch and the stamp
--               not read. The poll stamps these before it writes the stamp; the app's estimate counts them for the
--               warning. Once the workspace is stamped it answers nothing new.
-- Projects:  selltonai-database/supabase (owner); selltonai-modal calls both functions (brain signals poll);
--            selltonai calls both through its server routes (the history estimate, Settings > Signals).
-- Contract:  signal_scope_companies keeps the name, arguments and result columns of 421 and 426, so CREATE OR REPLACE
--            keeps every caller working. The new function has the same result columns. Goes first (merge order:
--            this S1, then Modal M1 judge fix, then Modal M2 parts B to E, then app A1).
-- Depends:   public.signal_scope_companies (426), public.brain_signal_cursor (421), public.campaigns,
--            public.campaign_companies, public.companies, public.organization_settings.
-- Rollback:  rollback/441_brain-signals-finished-plays-scope.rollback.sql
-- ============================================================

SET LOCAL lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.signal_scope_companies(
  organization_id text,
  include_without_domain boolean DEFAULT false
)
RETURNS TABLE (
  company_id uuid,
  domain text,
  linkedin_url text,
  brain_company_id bigint,
  brain_requested_at timestamptz,
  signals_history_read_at timestamptz,
  signals_history_skipped_at timestamptz
)
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  WITH marked_lists AS (
    SELECT marked.value AS list_id
    FROM public.organization_settings s
    CROSS JOIN LATERAL jsonb_array_elements_text(
      CASE WHEN jsonb_typeof(s.general_settings #> '{signals,list_ids}') = 'array'
           THEN s.general_settings #> '{signals,list_ids}'
           ELSE '[]'::jsonb END
    ) AS marked(value)
    WHERE s.organization_id = signal_scope_companies.organization_id
  ),
  finished_plays_on AS (
    -- 441: the poll has handled the companies of finished plays for this workspace, and the switch is not off.
    SELECT 1 AS on_
    WHERE EXISTS (
            SELECT 1 FROM public.brain_signal_cursor c
            WHERE c.environment = 'finished_plays:' || signal_scope_companies.organization_id
          )
      AND NOT EXISTS (
            SELECT 1 FROM public.organization_settings s
            WHERE s.organization_id = signal_scope_companies.organization_id
              AND s.general_settings #>> '{signals,finished_plays}' = 'false'
          )
  ),
  scope AS (
    -- In an active play. A company the gate blocked in that play is not being worked.
    SELECT pc.company_id
    FROM public.campaign_companies pc
    JOIN public.campaigns p ON p.id = pc.campaign_id
    WHERE pc.organization_id = signal_scope_companies.organization_id
      AND p.status = 'active'
      AND pc.blocked_by_icp IS NOT TRUE
    UNION
    -- 441 (D2, D3): in a finished play changed in the last 6 months, once the workspace is stamped (see above).
    SELECT pc.company_id
    FROM public.campaign_companies pc
    JOIN public.campaigns p ON p.id = pc.campaign_id
    CROSS JOIN finished_plays_on
    WHERE pc.organization_id = signal_scope_companies.organization_id
      AND p.status::text IN ('paused', 'discovery_completed', 'completed', 'fully_completed')
      AND p.updated_at >= now() - interval '6 months'
      AND pc.blocked_by_icp IS NOT TRUE
    UNION
    -- With a deal, open or closed (D1: Won and Lost both stay watched; D4: as long as the deal exists).
    SELECT d.company_id
    FROM public.deals d
    WHERE d.organization_id = signal_scope_companies.organization_id
    UNION
    -- In a list marked in settings, as a company.
    SELECT m.company_id
    FROM public.crm_list_members m
    JOIN marked_lists l ON l.list_id = m.list_id::text
    WHERE m.organization_id = signal_scope_companies.organization_id
      AND m.company_id IS NOT NULL
    UNION
    -- In a list marked in settings, through one of its people.
    SELECT link.company_id
    FROM public.crm_list_members m
    JOIN marked_lists l ON l.list_id = m.list_id::text
    JOIN public.company_contacts link
      ON link.contact_id = m.contact_id AND link.organization_id = m.organization_id
    WHERE m.organization_id = signal_scope_companies.organization_id
      AND m.contact_id IS NOT NULL
  )
  SELECT co.id, co.domain, co.linkedin_url, co.brain_company_id, co.brain_requested_at,
         co.signals_history_read_at, co.signals_history_skipped_at
  FROM scope
  JOIN public.companies co ON co.id = scope.company_id
  WHERE co.organization_id = signal_scope_companies.organization_id
    AND (signal_scope_companies.include_without_domain OR co.domain IS NOT NULL);
$$;

COMMENT ON FUNCTION public.signal_scope_companies(text, boolean) IS
  'The companies a workspace watches for Brain signals (D3): in an active play, in a finished play (paused, discovery_completed, completed, fully_completed) changed in the last 6 months once the poll stamped the workspace and general_settings.signals.finished_plays is not false (441), with a deal (open, Won or Lost, 426), or in a list marked in general_settings.signals.list_ids. By default only those with a domain, which is what a history read touches; include_without_domain lets the poll count the ones it skips.';

REVOKE ALL ON FUNCTION public.signal_scope_companies(text, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.signal_scope_companies(text, boolean) TO service_role;

CREATE OR REPLACE FUNCTION public.signal_finished_play_companies(
  organization_id text,
  include_without_domain boolean DEFAULT false
)
RETURNS TABLE (
  company_id uuid,
  domain text,
  linkedin_url text,
  brain_company_id bigint,
  brain_requested_at timestamptz,
  signals_history_read_at timestamptz,
  signals_history_skipped_at timestamptz
)
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  WITH finished AS (
    SELECT pc.company_id
    FROM public.campaign_companies pc
    JOIN public.campaigns p ON p.id = pc.campaign_id
    WHERE pc.organization_id = signal_finished_play_companies.organization_id
      AND p.status::text IN ('paused', 'discovery_completed', 'completed', 'fully_completed')
      AND p.updated_at >= now() - interval '6 months'
      AND pc.blocked_by_icp IS NOT TRUE
    EXCEPT
    SELECT s.company_id
    FROM public.signal_scope_companies(signal_finished_play_companies.organization_id, true) s
  )
  SELECT co.id, co.domain, co.linkedin_url, co.brain_company_id, co.brain_requested_at,
         co.signals_history_read_at, co.signals_history_skipped_at
  FROM finished
  JOIN public.companies co ON co.id = finished.company_id
  WHERE co.organization_id = signal_finished_play_companies.organization_id
    AND (signal_finished_play_companies.include_without_domain OR co.domain IS NOT NULL);
$$;

COMMENT ON FUNCTION public.signal_finished_play_companies(text, boolean) IS
  'The companies of finished plays (paused, discovery_completed, completed, fully_completed, changed in the last 6 months, not gate-blocked) that signal_scope_companies does not hold yet: what the finished-plays branch adds (441). The poll stamps them before it stamps the workspace; the app counts them for the past-signals warning. Empty once the workspace is stamped and its switch is on.';

REVOKE ALL ON FUNCTION public.signal_finished_play_companies(text, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.signal_finished_play_companies(text, boolean) TO service_role;

-- Verify:
-- select count(*) from public.signal_finished_play_companies('<org>', true);
--   -> before the poll stamps the workspace: the companies of its finished plays outside the scope
-- select environment, next_after from public.brain_signal_cursor where environment like 'finished_plays:%';
--   -> no row until the Modal poll of M2 runs; with no row the scope is exactly 426's
