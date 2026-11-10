-- ============================================================
-- Migration: 421_brain-signals-tables
-- Date:      2026-11-09
-- Purpose:   Brain signals (PLAN_BRAIN_SIGNALS_2026_11_09_REV4.md section 3.1).
--            1. companies.domain: a stored generated column from website (host, no scheme, no www., lower case), the
--               key a Brain signal is matched on (D10, G3). A website with no dot in its host gives NULL.
--               companies.brain_company_id, brain_requested_at, signals_history_read_at, signals_history_skipped_at.
--            2. signal_scope_companies(organization_id): the companies a workspace watches (D3) in one place, called
--               by the Modal poll and by the app's cost estimate, so the warning counts what the read will touch.
--            3. company_signals: global, one row per Brain signal id.
--            4. company_signal_workspace: one row per workspace and signal; the charge is made when it is first
--               created (section 3.6). The poll stores it as grade not_graded, next_action NULL.
--            5. company_signal_contact_use: which signal was used on which person (D16).
--            6. brain_signal_cursor: the poll's cursor, one row per environment.
-- Projects:  selltonai-database/supabase (owner); selltonai-modal writes all of it (brain signals poll, router,
--            writer helper); selltonai reads it through its server routes (company tab, signals list, estimate).
-- Contract:  Additive only. Service role only (no policies), as 418. The new tables are read by nothing until Modal
--            and the app ship, so this goes first (merge order S1, M1, A1, M2, A2, M3).
--            organization_settings.general_settings.signals (D12), the keys read here and by Modal:
--              enabled (bool), list_ids (array of crm_lists ids), history_mode ('all' | 'new_only', missing =
--              new_only), add_unknown (bool, missing = on), lookback_months (int, missing = 6), action_types (array).
--            Adding companies.domain rewrites the table under its lock: lock_timeout below makes a busy table fail
--            fast and the runner rolls the file back so it can be re-run.
-- Depends:   public.update_updated_at_column() (release_1.0.0; last re-declared by 300), public.deals (349),
--            public.crm_lists, public.crm_list_members (315), public.company_contacts, public.campaign_companies.
-- Rollback:  rollback/421_brain-signals-tables.rollback.sql
-- ============================================================

SET LOCAL lock_timeout = '10s';

-- 1. The company key and the stamps --------------------------------------------------------------

ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS domain text GENERATED ALWAYS AS (
    NULLIF(
      rtrim(substring(lower(btrim(website)) FROM '^(?:[a-z][a-z0-9+.-]*://)?(?:www\.)?([^/?#:@[:space:]]+\.[^/?#:@[:space:]]+)'), '.'),
      ''
    )
  ) STORED,
  ADD COLUMN IF NOT EXISTS brain_company_id bigint,
  ADD COLUMN IF NOT EXISTS brain_requested_at timestamptz,
  ADD COLUMN IF NOT EXISTS signals_history_read_at timestamptz,
  ADD COLUMN IF NOT EXISTS signals_history_skipped_at timestamptz;

COMMENT ON COLUMN public.companies.domain IS
  'Generated from website: host, no scheme, no www., lower case; NULL when website has no host with a dot. The key a Brain signal is matched on (company_signals.company_domain).';
COMMENT ON COLUMN public.companies.brain_company_id IS
  'Brain''s company id, set when a signal or an enrich answer names it.';
COMMENT ON COLUMN public.companies.brain_requested_at IS
  'When Sellton asked Brain to add this company (POST /v1/companies/enrich). Free to the customer (D4). The app''s waiting state reads it.';
COMMENT ON COLUMN public.companies.signals_history_read_at IS
  'When the one history read of this company was done (D20, D22). NULL = not read.';
COMMENT ON COLUMN public.companies.signals_history_skipped_at IS
  'Set when the workspace chose new_only and this company was already watched: no history read. Cleared when the workspace moves to all (D22).';

CREATE INDEX IF NOT EXISTS idx_companies_domain_organization
  ON public.companies (domain, organization_id)
  WHERE domain IS NOT NULL;

-- 2. The scope (D3) ------------------------------------------------------------------------------

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
  scope AS (
    -- In an active play. A company the gate blocked in that play is not being worked.
    SELECT pc.company_id
    FROM public.campaign_companies pc
    JOIN public.campaigns p ON p.id = pc.campaign_id
    WHERE pc.organization_id = signal_scope_companies.organization_id
      AND p.status = 'active'
      AND pc.blocked_by_icp IS NOT TRUE
    UNION
    -- With an open deal.
    SELECT d.company_id
    FROM public.deals d
    WHERE d.organization_id = signal_scope_companies.organization_id
      AND d.closed_at IS NULL
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
  'The companies a workspace watches for Brain signals (D3): in an active play, with an open deal, or in a list marked in general_settings.signals.list_ids. By default only those with a domain, which is what a history read touches; include_without_domain lets the poll count the ones it skips.';

REVOKE ALL ON FUNCTION public.signal_scope_companies(text, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.signal_scope_companies(text, boolean) TO service_role;

-- 3. The signals, global -------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.company_signals (
  brain_signal_id bigint PRIMARY KEY,
  signal_hash text,
  brain_company_id bigint,
  company_domain text NOT NULL,
  company_name text,
  signal_type text NOT NULL,
  signal_strength text,
  priority_score numeric,
  title text,
  summary text,
  url text,
  source text,
  detected_at timestamptz,
  occurred_at date,
  date_precision text,
  date_basis text,
  key_facts jsonb NOT NULL DEFAULT '{}'::jsonb,
  received_via text NOT NULL CHECK (received_via IN ('poll', 'history')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.company_signals IS
  'Brain signals, global, one row per Brain signal id. A signal that comes again is an update: no charge and no new action. received_via is what first brought it and does not change: the router only takes poll rows (G10).';

CREATE INDEX IF NOT EXISTS company_signals_domain_occurred_idx
  ON public.company_signals (company_domain, occurred_at);
CREATE INDEX IF NOT EXISTS company_signals_type_idx
  ON public.company_signals (signal_type);

DROP TRIGGER IF EXISTS update_company_signals_updated_at ON public.company_signals;
CREATE TRIGGER update_company_signals_updated_at
  BEFORE UPDATE ON public.company_signals
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

ALTER TABLE public.company_signals ENABLE ROW LEVEL SECURITY;
-- No policies on purpose: the service role (Modal, the app's server routes) reads and writes; browser keys see nothing.

-- 4. Per workspace -------------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.company_signal_workspace (
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  brain_signal_id bigint NOT NULL REFERENCES public.company_signals(brain_signal_id) ON DELETE CASCADE,
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  grade text NOT NULL DEFAULT 'not_graded' CHECK (grade IN ('none', 'relevant', 'central', 'not_graded')),
  reason text,
  goal_source text CHECK (goal_source IN ('deal', 'play', 'brand')),
  next_action text,
  task_id uuid REFERENCES public.tasks(id) ON DELETE SET NULL,
  deal_id uuid REFERENCES public.deals(id) ON DELETE SET NULL,
  seen_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (organization_id, brain_signal_id)
);

COMMENT ON TABLE public.company_signal_workspace IS
  'A Brain signal as one workspace holds it. The usage row is written when this row is first created (section 3.6). The poll stores grade not_graded, next_action NULL; the router fills them.';

CREATE INDEX IF NOT EXISTS company_signal_workspace_org_created_idx
  ON public.company_signal_workspace (organization_id, created_at DESC);
CREATE INDEX IF NOT EXISTS company_signal_workspace_company_idx
  ON public.company_signal_workspace (company_id);
CREATE INDEX IF NOT EXISTS company_signal_workspace_to_route_idx
  ON public.company_signal_workspace (created_at)
  WHERE grade = 'not_graded' AND next_action IS NULL;

ALTER TABLE public.company_signal_workspace ENABLE ROW LEVEL SECURITY;
-- No policies on purpose, as above.

-- 5. Use per person (D16) ------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.company_signal_contact_use (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  brain_signal_id bigint NOT NULL REFERENCES public.company_signals(brain_signal_id) ON DELETE CASCADE,
  contact_id uuid NOT NULL REFERENCES public.contacts(id) ON DELETE CASCADE,
  task_id uuid REFERENCES public.tasks(id) ON DELETE SET NULL,
  used_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.company_signal_contact_use IS
  'One row per use of a signal on a person, across plays and deals (D16: relevant once, central twice). task_id is NULL for LinkedIn sequence drafts, which have no task until the claim route (G9).';

CREATE INDEX IF NOT EXISTS company_signal_contact_use_lookup_idx
  ON public.company_signal_contact_use (organization_id, contact_id, brain_signal_id);
CREATE INDEX IF NOT EXISTS company_signal_contact_use_task_idx
  ON public.company_signal_contact_use (task_id)
  WHERE task_id IS NOT NULL;

ALTER TABLE public.company_signal_contact_use ENABLE ROW LEVEL SECURITY;
-- No policies on purpose, as above.

-- 6. The poll's cursor ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.brain_signal_cursor (
  environment text PRIMARY KEY,
  next_after text NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.brain_signal_cursor IS
  'The poll''s place in GET /v1/signals, one row per environment. next_after is Brain''s opaque cursor, sent back unchanged. Rows keyed tidy:actively_hiring and history_mode:<organization id> are the same run''s own bookkeeping (the day of the last tidy, the history mode of the last run).';

DROP TRIGGER IF EXISTS update_brain_signal_cursor_updated_at ON public.brain_signal_cursor;
CREATE TRIGGER update_brain_signal_cursor_updated_at
  BEFORE UPDATE ON public.brain_signal_cursor
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();

ALTER TABLE public.brain_signal_cursor ENABLE ROW LEVEL SECURITY;
-- No policies on purpose, as above.

-- Verify:
-- select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'company_signals';
--   -> 20
-- select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'company_signal_workspace';
--   -> 11
-- select column_name, is_generated from information_schema.columns
--  where table_schema = 'public' and table_name = 'companies' and column_name = 'domain';
--   -> domain, ALWAYS
-- select count(*) from public.signal_scope_companies('<organization id>');
