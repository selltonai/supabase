-- ============================================================
-- Migration: 438_gtm-strategy-tables
-- Date:      2026-11-12
-- Purpose:   GTM strategy (CONTRACT_GTM_STRATEGY_2026_11_12.md, sections Names, Availability, Database): the tables, two
--            notification types and the usage label of the new "Strategy" tab.
--              1. gtm_strategies: one row per strategy run of a workspace (status running, ready or failed; mode auto
--                 or together; the answers the customer gave, the offer typed when the Knowledge Brain is thin, the
--                 availability at the start, the plays count, model cost and billed amount, the stop code).
--              2. gtm_strategy_plays: the plays a run proposes (at most 5 per run, enforced by the backend), the customer's
--                 edits, the sources and the missing pieces, and the campaign it became when the customer drafts it
--                 (campaign_id, set null if that campaign is deleted).
--              3. gtm_strategy_suggestions: the daily document check's suggestions (a new document that could feed a
--                 play), with the notification time.
--              4. notifications.type: two values added, strategy_ready and strategy_suggestion, to the CHECK installed on
--                 the database, the way 376 added call_due: the live expression is read and extended, so every value
--                 other branches added stays.
--              5. usage_analytics_projection_contribution: two additions to the newest definition (431), nothing else.
--                 In derived_task_label, metadata.service gtm_strategy gives 'Strategy' (it was 'LLM generation'). In
--                 the units column, a gtm_strategy row counts 1 (one unit per run; the backend writes one usage row per
--                 run) whatever its category (the model providers fall in tokens, where units were 0).
--                 action_label_map gets the same service with the label Strategy, in the form of 431's rows.
--            The function body is 431's (lines 32 to 270) byte for byte, plus exactly four added lines: the two
--            comments `-- 438: ...`, the `WHEN c.service_name = 'gtm_strategy' THEN 'Strategy'` line and the
--            `WHEN m.service_name = 'gtm_strategy' THEN 1` line. 431 is the newest definition on stage (396 before it);
--            no later migration redefines the function.
-- Projects:  selltonai-database/supabase (owner); selltonai-modal (gtm_strategy router and writers) reads and writes the three
--            tables with the service role; selltonai (app, Strategy tab) reads them through the backend.
-- Contract:  Additive. Service role only on the three tables: RLS on with no policies, anon and authenticated hold no
--            privileges (the form of 421 and 435). One CHECK widened (nothing already allowed is removed), one function
--            replaced with the same signature and result type (CREATE OR REPLACE keeps its grants and the insert
--            trigger that calls it), one row in action_label_map. Idempotent: IF NOT EXISTS, the CHECK is only
--            extended when a value is missing, OR REPLACE, ON CONFLICT DO UPDATE.
--            Merge order: this PR (supabase), then the selltonai-modal GTM strategy PR, then the selltonai app GTM
--            strategy PR.
-- Depends:   public.organization, public.campaigns, public.notifications (type CHECK, 376), public.action_label_map (249),
--            public.usage_analytics_projection_contribution (345, 396, 431).
-- Rollback:  rollback/438_gtm-strategy-tables.rollback.sql (drops the three tables, deletes the two notification types'
--            rows and takes the two values out of the CHECK, restores 431's function and removes the label row).
-- ============================================================

SET LOCAL lock_timeout = '10s';

-- 1. The run -------------------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.gtm_strategies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  requested_by text,
  status text NOT NULL DEFAULT 'running' CHECK (status IN ('running', 'ready', 'failed')),
  mode text NOT NULL DEFAULT 'auto' CHECK (mode IN ('auto', 'together')),
  focus text,
  answers jsonb,
  offer text,
  availability text CHECK (availability IN ('ready', 'thin', 'empty')),
  plays_count integer NOT NULL DEFAULT 0 CHECK (plays_count >= 0),
  cost_usd numeric,
  billed_usd numeric,
  error_code text,
  documents_checked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz
);

COMMENT ON TABLE public.gtm_strategies IS
  'One GTM strategy run of a workspace. requested_by is the Clerk user id. availability: ready (Brand DNA and a processed document besides the onboarding ones), thin (Brand DNA only, the offer is typed first), empty (no Brand DNA, no run is offered). cost_usd is the model cost, billed_usd what the workspace is charged (price list multiplier). error_code: the stop code of a run that ended failed. documents_checked_at: when the daily document check last read this strategy.';

CREATE INDEX IF NOT EXISTS gtm_strategies_org_created_idx
  ON public.gtm_strategies (organization_id, created_at DESC);

REVOKE ALL ON TABLE public.gtm_strategies FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.gtm_strategies TO service_role;
ALTER TABLE public.gtm_strategies ENABLE ROW LEVEL SECURITY;
-- No policies on purpose: the service role (Modal, the app's server routes) reads and writes; browser keys see nothing.

-- 2. The plays of a run --------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.gtm_strategy_plays (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  strategy_id uuid NOT NULL REFERENCES public.gtm_strategies(id) ON DELETE CASCADE,
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  position integer,
  play_key text,
  title text,
  reason text,
  brief text,
  brief_original text,
  targeting jsonb,
  channel text CHECK (channel IN ('email', 'linkedin')),
  sources jsonb NOT NULL DEFAULT '[]'::jsonb,
  missing jsonb NOT NULL DEFAULT '[]'::jsonb,
  checks jsonb,
  status text NOT NULL DEFAULT 'proposed' CHECK (status IN ('proposed', 'edited', 'drafted', 'dismissed')),
  campaign_id uuid REFERENCES public.campaigns(id) ON DELETE SET NULL,
  edited_by text,
  edited_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.gtm_strategy_plays IS
  'A play proposed by a gtm_strategies run. brief is what the customer sees and edits, brief_original what Sellton wrote. targeting: job_titles[], industries[], regions[], min_employees, max_employees. sources: list of {file_id, file_name}. missing: list of short noun phrases. checks: the result of the checks on the brief. campaign_id: the draft play created from this row (null until then, and null again if that campaign is deleted). Nothing here is ever launched or sent.';

CREATE INDEX IF NOT EXISTS gtm_strategy_plays_org_created_idx
  ON public.gtm_strategy_plays (organization_id, created_at DESC);
CREATE INDEX IF NOT EXISTS gtm_strategy_plays_strategy_idx
  ON public.gtm_strategy_plays (strategy_id, position);
CREATE INDEX IF NOT EXISTS gtm_strategy_plays_campaign_idx
  ON public.gtm_strategy_plays (campaign_id)
  WHERE campaign_id IS NOT NULL;

REVOKE ALL ON TABLE public.gtm_strategy_plays FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.gtm_strategy_plays TO service_role;
ALTER TABLE public.gtm_strategy_plays ENABLE ROW LEVEL SECURITY;
-- No policies on purpose, as above.

-- 3. The suggestions of the daily document check -------------------------------------------------

CREATE TABLE IF NOT EXISTS public.gtm_strategy_suggestions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  strategy_id uuid NOT NULL REFERENCES public.gtm_strategies(id) ON DELETE CASCADE,
  file_ids jsonb NOT NULL DEFAULT '[]'::jsonb,
  play_key text,
  title text,
  reason text,
  status text NOT NULL DEFAULT 'new' CHECK (status IN ('new', 'used', 'dismissed')),
  created_at timestamptz NOT NULL DEFAULT now(),
  notified_at timestamptz
);

COMMENT ON TABLE public.gtm_strategy_suggestions IS
  'A suggestion written by the daily document check: new documents (file_ids, organization_files ids) that could feed a play of the strategy. notified_at: when the strategy_suggestion notification was created (null until then).';

CREATE INDEX IF NOT EXISTS gtm_strategy_suggestions_org_created_idx
  ON public.gtm_strategy_suggestions (organization_id, created_at DESC);
CREATE INDEX IF NOT EXISTS gtm_strategy_suggestions_strategy_idx
  ON public.gtm_strategy_suggestions (strategy_id);

REVOKE ALL ON TABLE public.gtm_strategy_suggestions FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.gtm_strategy_suggestions TO service_role;
ALTER TABLE public.gtm_strategy_suggestions ENABLE ROW LEVEL SECURITY;
-- No policies on purpose, as above.

-- 4. Notification types ----------------------------------------------------------------------------
-- Extend the CHECK that is installed instead of rebuilding a list (the form of 376): every value other branches added stays.

DO $$
DECLARE v_expression text;
BEGIN
  SELECT pg_get_expr(conbin, conrelid) INTO STRICT v_expression
  FROM pg_constraint WHERE conrelid = 'public.notifications'::regclass
    AND conname = 'notifications_type_check';
  IF position('strategy_ready' IN v_expression) = 0 OR position('strategy_suggestion' IN v_expression) = 0 THEN
    ALTER TABLE public.notifications DROP CONSTRAINT notifications_type_check;
    EXECUTE 'ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check CHECK (('
      || v_expression || ') OR type = ''strategy_ready'' OR type = ''strategy_suggestion'')';
  END IF;
END $$;

-- 5. Usage page label ------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.usage_analytics_projection_contribution(p_usage usage)
 RETURNS SETOF usage_analytics_projection_contributions
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  WITH base_usage AS (
    SELECT
      p_usage.organization_id,
      p_usage.created_at AS occurred_at,
      p_usage.provider,
      p_usage.model_name,
      p_usage.campaign_id,
      p_usage.user_id,
      p_usage.run_id,
      COALESCE(p_usage.api_calls, 0)::numeric AS api_calls,
      COALESCE(p_usage.input_tokens, 0)::numeric AS input_tokens,
      COALESCE(p_usage.output_tokens, 0)::numeric AS output_tokens,
      (
        CASE
          WHEN COALESCE(p_usage.total_tokens, 0) > 0 THEN COALESCE(p_usage.total_tokens, 0)
          ELSE COALESCE(p_usage.input_tokens, 0) + COALESCE(p_usage.output_tokens, 0)
        END
      )::numeric AS total_tokens,
      COALESCE(p_usage.original_cost, 0)::numeric AS original_cost,
      COALESCE(p_usage.sellton_cost, 0)::numeric AS sellton_cost,
      public.usage_metadata_object(p_usage.metadata) AS metadata
    WHERE p_usage.created_at IS NOT NULL
  ),
  categorized AS (
    SELECT
      b.*,
      lower(trim(COALESCE(b.metadata ->> 'action', ''))) AS action_key,
      COALESCE(NULLIF(b.metadata ->> 'provider_name', ''), b.provider, '') AS provider_name,
      COALESCE(
        NULLIF(b.metadata ->> 'effective_provider', ''),
        NULLIF(b.metadata ->> 'provider', ''),
        NULLIF(b.metadata ->> 'provider_name', ''),
        b.provider,
        ''
      ) AS effective_provider,
      COALESCE(b.metadata ->> 'research_flow', '') AS research_flow,
      COALESCE(b.metadata ->> 'service', '') AS service_name,
      COALESCE(b.metadata ->> 'operation', '') AS operation_name,
      CASE
        WHEN b.provider = 'airscale'
          AND (
            COALESCE(b.metadata ->> 'action', '') = 'phone_finder'
            OR COALESCE(b.model_name, '') LIKE 'airscale-phone%'
          ) THEN 'phones'
        -- 396 (KAN-333 X1): Sellton Brain's phone finding is phones, as Airscale's is; every other brain row stays b2b_data.
        WHEN b.provider = 'brain' AND COALESCE(b.metadata ->> 'action', '') = 'phone_finder' THEN 'phones'
        -- 396: the phone's voice (ElevenLabs characters) counts with the token providers, so it shows under Research.
        WHEN b.provider IN ('openai', 'anthropic', 'deepseek', 'togetherai', 'perplexity', 'gemini', 'mistral', 'xai', 'grok', 'elevenlabs') THEN 'tokens'
        ELSE 'b2b_data'
      END AS derived_category
    FROM base_usage b
  ),
  labeled AS (
    SELECT
      c.*,
      CASE
        WHEN c.service_name = 'company_research' THEN
          CASE
            WHEN c.effective_provider = 'both' AND c.provider_name = 'gemini' THEN 'Company research · Gemini Summarizer'
            WHEN c.effective_provider = 'both' AND c.provider_name <> '' THEN 'Company research · ' || public.usage_provider_label(c.provider_name)
            WHEN c.effective_provider = 'both' THEN 'Company research · Multi-provider'
            WHEN c.effective_provider = 'gemini_ultra_lean' OR c.research_flow = 'ultra_lean' THEN 'Company research · Gemini Ultra Lean'
            WHEN c.effective_provider IN ('grok', 'xai') OR c.research_flow = 'advanced_research' THEN 'Company research · Advanced Research'
            WHEN c.effective_provider = 'gemini_pro' OR c.research_flow = 'gemini_pro' THEN 'Company research · Gemini Pro Legacy'
            WHEN (c.effective_provider = 'gemini' OR c.provider_name = 'gemini') AND c.research_flow = 'compact' THEN 'Company research · Gemini Compact'
            WHEN c.effective_provider <> '' THEN 'Company research · ' || public.usage_provider_label(c.effective_provider)
            WHEN c.provider_name <> '' THEN 'Company research · ' || public.usage_provider_label(c.provider_name)
            ELSE 'Company research · Unknown'
          END
        -- 431: Brain signals of the web app
        WHEN c.service_name IN ('brain_signals', 'brain_signal_router') THEN 'Signals'
        -- 438: GTM strategy runs
        WHEN c.service_name = 'gtm_strategy' THEN 'Strategy'
        WHEN c.provider = 'gemini' AND public.usage_metadata_number(c.metadata, 'grounding_queries') > 0 THEN 'Web search (grounding)'
        WHEN c.derived_category = 'phones' THEN 'Phone discovery'
        WHEN c.provider IN ('hunter', 'icypeas', 'apollo') THEN 'Email finder'
        WHEN c.provider = 'exa' THEN 'Web research'
        WHEN c.provider = 'ai_ark' AND (c.action_key = 'similar_companies' OR COALESCE(c.model_name, '') LIKE '%similar_companies%') THEN 'Company search'
        WHEN c.provider = 'ai_ark' AND (c.action_key = 'person_profile' OR COALESCE(c.model_name, '') LIKE '%person_profile%') THEN 'Contact enrichment'
        WHEN c.provider = 'ai_ark' THEN 'People search'
        WHEN c.provider = 'b2b_enrichment' AND COALESCE(c.model_name, '') LIKE 'b2b-email_verifier%' THEN 'Email verifier'
        WHEN c.provider = 'b2b_enrichment' AND COALESCE(c.model_name, '') LIKE 'b2b-email_finder%' THEN 'Email finder'
        WHEN c.provider = 'b2b_enrichment' AND COALESCE(c.model_name, '') LIKE 'b2b-people_search%' THEN 'People search'
        WHEN c.provider = 'b2b_enrichment' AND COALESCE(c.model_name, '') LIKE 'b2b-similar_companies%' THEN 'Company search'
        WHEN c.provider = 'b2b_enrichment' AND COALESCE(c.model_name, '') LIKE 'b2b-company_profile%' THEN 'Company search'
        WHEN c.provider = 'b2b_enrichment' THEN 'Contact enrichment'
        ELSE 'LLM generation'
      END AS derived_task_label,
      CASE
        WHEN c.derived_category = 'tokens' THEN c.model_name
        ELSE NULL
      END AS derived_model_label
    FROM categorized c
  ),
  metric_inputs AS (
    SELECT
      l.*,
      public.usage_metadata_count(
        l.metadata,
        VARIADIC ARRAY[
          'found_emails', 'emails_found', 'email_matches', 'returned_email_matches',
          'returned_emails', 'emails_returned', 'emails', 'email_found', 'found_email', 'email'
        ]
      ) AS found_emails_raw,
      public.usage_metadata_count(
        l.metadata,
        VARIADIC ARRAY[
          'profiles_returned', 'people_found', 'people_returned', 'returned_people',
          'returned_profiles', 'profile_count', 'profiles_found', 'results_found'
        ]
      ) AS people_returned_raw,
      public.usage_metadata_count(
        l.metadata,
        VARIADIC ARRAY[
          'companies_found', 'companies_returned', 'returned_companies', 'company_count',
          'company_profiles_returned', 'similar_companies'
        ]
      ) AS companies_returned_raw,
      public.usage_metadata_count(l.metadata, VARIADIC ARRAY['results', 'items', 'data']) AS generic_results,
      public.usage_metadata_count(
        l.metadata,
        VARIADIC ARRAY[
          'phones_found', 'phone_found', 'phone_number', 'phone_numbers', 'phone',
          'phones', 'mobile_phone', 'mobile'
        ]
      ) AS phones_found_raw,
      public.usage_metadata_number(l.metadata, 'billable_units') AS billable_units,
      public.usage_metadata_number(l.metadata, 'grounding_queries') AS metadata_grounding_queries,
      public.usage_metadata_boolean(l.metadata, 'success') AS is_success,
      (
        l.action_key = 'people_search'
        OR COALESCE(l.model_name, '') LIKE '%people_search%'
        OR (l.provider = 'ai_ark' AND l.action_key = '')
      ) AS is_people_search,
      (
        l.action_key IN ('similar_companies', 'company_search', 'company_profile')
        OR COALESCE(l.model_name, '') LIKE '%similar_companies%'
        OR COALESCE(l.model_name, '') LIKE '%company_profile%'
      ) AS is_company_search,
      (
        l.provider IN ('hunter', 'icypeas')
        OR (l.provider = 'apollo' AND (l.action_key = 'email_finder' OR COALESCE(l.model_name, '') LIKE '%email_finder%'))
        OR (l.provider = 'airscale' AND (l.action_key = 'email_finder' OR COALESCE(l.model_name, '') LIKE '%email_finder%'))
        OR (l.provider = 'b2b_enrichment' AND COALESCE(l.model_name, '') LIKE 'b2b-email_finder%')
      ) AS is_email_provider
    FROM labeled l
  ),
  metric_resolved AS (
    SELECT
      m.*,
      CASE
        WHEN m.found_emails_raw > 0 THEN m.found_emails_raw
        WHEN m.billable_units > 0 AND m.is_email_provider THEN m.billable_units
        ELSE 0
      END AS resolved_emails_found,
      CASE
        WHEN m.people_returned_raw > 0 THEN m.people_returned_raw
        WHEN m.is_people_search THEN m.generic_results
        ELSE 0
      END AS resolved_people_found,
      CASE
        WHEN m.companies_returned_raw > 0 THEN m.companies_returned_raw
        WHEN m.is_company_search THEN m.generic_results
        ELSE 0
      END AS resolved_companies_found
    FROM metric_inputs m
  ),
  metrics AS (
    SELECT
      r.*,
      CASE
        WHEN r.derived_category = 'phones' THEN COALESCE(NULLIF(r.phones_found_raw, 0), CASE WHEN r.is_success THEN 1 ELSE 0 END)
        ELSE 0
      END AS phones_found,
      CASE
        WHEN r.derived_category = 'b2b_data' THEN r.resolved_emails_found
        ELSE 0
      END AS emails_found,
      CASE
        WHEN r.derived_category = 'b2b_data' AND r.resolved_people_found > 0 AND NOT r.is_company_search THEN r.resolved_people_found
        WHEN r.derived_category = 'b2b_data'
          AND (r.resolved_emails_found + r.resolved_people_found + r.resolved_companies_found) = 0
          AND r.billable_units > 0
          AND r.is_people_search THEN r.billable_units
        ELSE 0
      END AS people_found,
      CASE
        WHEN r.derived_category = 'b2b_data' AND r.resolved_companies_found > 0 THEN r.resolved_companies_found
        WHEN r.derived_category = 'b2b_data'
          AND (r.resolved_emails_found + r.resolved_people_found + r.resolved_companies_found) = 0
          AND r.billable_units > 0
          AND r.is_company_search THEN r.billable_units
        WHEN r.derived_category = 'b2b_data'
          AND (r.resolved_emails_found + r.resolved_people_found + r.resolved_companies_found) = 0
          AND r.provider = 'b2b_enrichment'
          AND COALESCE(r.model_name, '') LIKE 'b2b-company_profile%' THEN COALESCE(NULLIF(r.billable_units, 0), 1)
        ELSE 0
      END AS companies_found
    FROM metric_resolved r
  )
  SELECT
    p_usage.id,
    m.organization_id,
    m.occurred_at,
    m.derived_category,
    COALESCE(m.campaign_id, ''),
    COALESCE(m.user_id, ''),
    m.derived_task_label,
    COALESCE(m.derived_model_label, ''),
    COALESCE(m.model_name, ''),
    COALESCE(m.service_name, ''),
    COALESCE(m.operation_name, ''),
    COALESCE(m.metadata ->> 'company_id', ''),
    COALESCE(m.run_id, ''),
    COALESCE(m.metadata ->> 'research_run_id', ''),
    m.api_calls::bigint,
    m.input_tokens::bigint,
    m.output_tokens::bigint,
    m.total_tokens::bigint,
    m.metadata_grounding_queries::bigint,
    CASE
      WHEN m.derived_category = 'phones' THEN m.phones_found
      -- 438: one strategy run is one unit, whatever the provider category
      WHEN m.service_name = 'gtm_strategy' THEN 1
      WHEN m.derived_category = 'b2b_data' AND m.service_name = 'brain_signals' THEN 1
      WHEN m.derived_category = 'b2b_data' THEN m.emails_found + m.people_found + m.companies_found
      ELSE 0
    END,
    m.emails_found,
    m.people_found,
    m.companies_found,
    m.phones_found,
    m.original_cost,
    m.sellton_cost,
    now()
  FROM metrics m;
$function$;

INSERT INTO public.action_label_map (provider, service_name, model_name_pattern, requires_grounding, task_key, display_label, priority) VALUES
  ('', 'gtm_strategy', '', false, 'strategy', 'Strategy', 1)
ON CONFLICT (provider, service_name, model_name_pattern, requires_grounding, task_key) DO UPDATE SET display_label = EXCLUDED.display_label, priority = EXCLUDED.priority;

-- Verify (read-only, inside a rolled-back transaction on stage):
--   SELECT conname, pg_get_expr(conbin, conrelid) FROM pg_constraint WHERE conname = 'notifications_type_check';  -- holds strategy_ready, strategy_suggestion and every earlier value
--   SELECT service_name, task_key, display_label FROM public.action_label_map WHERE service_name = 'gtm_strategy';  -- 1 row, Strategy
--   -- a gtm_strategy usage row projects with task label Strategy, units 1:
--   SELECT * FROM public.usage_analytics_projection_contribution(
--     jsonb_populate_record(NULL::public.usage, '{"id":"00000000-0000-0000-0000-000000000002","organization_id":"org_x","provider":"anthropic","model_name":"claude-sonnet","metadata":{"service":"gtm_strategy"},"created_at":"2026-11-12T10:00:00Z"}'::jsonb));
