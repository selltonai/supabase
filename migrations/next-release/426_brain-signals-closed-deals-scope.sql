-- ============================================================
-- Migration: 426_brain-signals-closed-deals-scope
-- Date:      2026-11-11
-- Purpose:   Brain signals follow closed deals (PLAN_BRAIN_SIGNALS_CLOSED_DEALS_2026_11_10.md, D1 and D4).
--            signal_scope_companies(organization_id): the deal branch reads every deal of the workspace, open, Won
--            and Lost, instead of open deals only (closed_at IS NULL in 421). A closed deal keeps its company watched
--            as long as the deal exists (D4). The other three branches (active play, marked list as a company,
--            marked list through a person) are as in 421.
-- Projects:  selltonai-database/supabase (owner); selltonai-modal calls it (brain signals poll); selltonai calls it
--            through its server route for the history cost estimate, which so counts the closed deals with no app
--            change.
-- Contract:  Same name, arguments and result columns as 421, so CREATE OR REPLACE keeps every caller working. Goes
--            before the Modal PR (merge order: this S2, then Modal M4).
-- Depends:   public.signal_scope_companies and the companies columns of 421, public.deals.
-- Rollback:  rollback/426_brain-signals-closed-deals-scope.rollback.sql
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
  scope AS (
    -- In an active play. A company the gate blocked in that play is not being worked.
    SELECT pc.company_id
    FROM public.campaign_companies pc
    JOIN public.campaigns p ON p.id = pc.campaign_id
    WHERE pc.organization_id = signal_scope_companies.organization_id
      AND p.status = 'active'
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
  'The companies a workspace watches for Brain signals (D3): in an active play, with a deal (open, Won or Lost, 426), or in a list marked in general_settings.signals.list_ids. By default only those with a domain, which is what a history read touches; include_without_domain lets the poll count the ones it skips.';

REVOKE ALL ON FUNCTION public.signal_scope_companies(text, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.signal_scope_companies(text, boolean) TO service_role;

-- Verify:
-- select count(*) from public.deals where closed_at is not null and organization_id = '<org>';
-- select count(*) from public.signal_scope_companies('<org>', true) s
--   join public.deals d on d.company_id = s.company_id where d.closed_at is not null;
--   -> every company of a closed deal of that workspace is in the scope
