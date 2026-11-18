-- Reverses 426: the deal branch of signal_scope_companies reads open deals only again, as 421 left it. Nothing else
-- needs to go first: the Modal router reads closed deals itself, and with this rolled back their companies are simply
-- no longer polled.
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
