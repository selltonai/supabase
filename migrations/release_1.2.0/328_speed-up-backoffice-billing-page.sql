-- Speed up Backoffice billing workspace list.
--
-- What changed:
--   - Adds a DB-side rollup RPC for Backoffice /billing.
--   - Aggregates usage, uninvoiced usage, invoices, customer state, and
--     workspace work-access fields into one row per workspace.
--   - Adds period-oriented indexes for the rollup query shape.
--
-- Projects depending on this:
--   - backoffice reads backoffice_billing_workspace_rollup_v1() for /billing.
--   - selltonai-modal keeps writing usage, billing_customers, and
--     billing_invoices with the same existing shapes.
--
-- Application code update:
--   - Deploy with backoffice SupabaseAdminService fast-path update.
--   - No existing table, view, or API response shape is changed.

CREATE INDEX IF NOT EXISTS idx_usage_backoffice_billing_period_org
  ON public.usage (created_at DESC, organization_id)
  INCLUDE (original_cost, sellton_cost, total_tokens, api_calls, user_id, invoice_id)
  WHERE created_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_billing_invoices_backoffice_period_org
  ON public.billing_invoices (period_end DESC, organization_id)
  INCLUDE (status, total, created_at, period_start);

CREATE OR REPLACE FUNCTION public.backoffice_billing_workspace_rollup_v1(
  p_start timestamptz,
  p_end timestamptz
)
RETURNS TABLE (
  organization_id text,
  org_name text,
  total_original_cost numeric,
  total_sellton_cost numeric,
  total_tokens bigint,
  api_calls bigint,
  usage_rows bigint,
  user_count bigint,
  uninvoiced_sellton_cost numeric,
  invoice_total numeric,
  invoice_count bigint,
  paid_invoice_count bigint,
  open_invoice_count bigint,
  failed_invoice_count bigint,
  last_usage_at timestamptz,
  last_invoice_at timestamptz,
  billing_status text,
  auto_charge_enabled boolean,
  billing_email text,
  card_brand text,
  card_last4 text,
  monthly_spend_limit numeric,
  work_access_mode text,
  work_access_reason text,
  work_access_until timestamptz,
  work_access_updated_by text,
  work_access_updated_at timestamptz,
  dispatch_suspended boolean,
  dispatch_suspended_reason text,
  dispatch_suspended_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH usage_rollup AS (
    SELECT
      u.organization_id,
      SUM(COALESCE(u.original_cost, 0)) AS total_original_cost,
      SUM(COALESCE(u.sellton_cost, 0)) AS total_sellton_cost,
      SUM(COALESCE(u.total_tokens, 0))::bigint AS total_tokens,
      SUM(COALESCE(u.api_calls, 0))::bigint AS api_calls,
      COUNT(*)::bigint AS usage_rows,
      COUNT(DISTINCT u.user_id) FILTER (WHERE u.user_id IS NOT NULL) AS user_count,
      SUM(COALESCE(u.sellton_cost, 0)) FILTER (WHERE u.invoice_id IS NULL) AS uninvoiced_sellton_cost,
      MAX(u.created_at) AS last_usage_at
    FROM public.usage u
    WHERE u.created_at >= p_start
      AND u.created_at < p_end
    GROUP BY u.organization_id
  ),
  invoice_rollup AS (
    SELECT
      bi.organization_id,
      SUM(COALESCE(bi.total, 0)) AS invoice_total,
      COUNT(*)::bigint AS invoice_count,
      COUNT(*) FILTER (WHERE bi.status = 'paid') AS paid_invoice_count,
      COUNT(*) FILTER (WHERE bi.status IN ('open', 'sent', 'draft')) AS open_invoice_count,
      COUNT(*) FILTER (WHERE bi.status = 'failed') AS failed_invoice_count,
      MAX(COALESCE(bi.created_at, bi.period_end, bi.period_start)) AS last_invoice_at
    FROM public.billing_invoices bi
    WHERE bi.period_end >= p_start
      AND bi.period_end < p_end
    GROUP BY bi.organization_id
  ),
  workspace_ids AS (
    SELECT o.id AS organization_id
    FROM public.organization o
    WHERE o.deleted IS DISTINCT FROM TRUE

    UNION

    SELECT bc.organization_id
    FROM public.billing_customers bc
    WHERE bc.organization_id IS NOT NULL

    UNION

    SELECT ur.organization_id
    FROM usage_rollup ur
    WHERE ur.organization_id IS NOT NULL

    UNION

    SELECT ir.organization_id
    FROM invoice_rollup ir
    WHERE ir.organization_id IS NOT NULL
  )
  SELECT
    wi.organization_id,
    COALESCE(o.name, '') AS org_name,
    COALESCE(ur.total_original_cost, 0) AS total_original_cost,
    COALESCE(ur.total_sellton_cost, 0) AS total_sellton_cost,
    COALESCE(ur.total_tokens, 0)::bigint AS total_tokens,
    COALESCE(ur.api_calls, 0)::bigint AS api_calls,
    COALESCE(ur.usage_rows, 0)::bigint AS usage_rows,
    COALESCE(ur.user_count, 0)::bigint AS user_count,
    COALESCE(ur.uninvoiced_sellton_cost, 0) AS uninvoiced_sellton_cost,
    COALESCE(ir.invoice_total, 0) AS invoice_total,
    COALESCE(ir.invoice_count, 0)::bigint AS invoice_count,
    COALESCE(ir.paid_invoice_count, 0)::bigint AS paid_invoice_count,
    COALESCE(ir.open_invoice_count, 0)::bigint AS open_invoice_count,
    COALESCE(ir.failed_invoice_count, 0)::bigint AS failed_invoice_count,
    ur.last_usage_at,
    ir.last_invoice_at,
    bc.status AS billing_status,
    bc.auto_charge_enabled,
    bc.billing_email,
    bc.card_brand,
    bc.card_last4,
    bc.monthly_spend_limit,
    o.work_access_mode,
    o.work_access_reason,
    o.work_access_until,
    o.work_access_updated_by,
    o.work_access_updated_at,
    COALESCE(o.dispatch_suspended, FALSE) AS dispatch_suspended,
    o.dispatch_suspended_reason,
    o.dispatch_suspended_at
  FROM workspace_ids wi
  LEFT JOIN public.organization o ON o.id = wi.organization_id
  LEFT JOIN public.billing_customers bc ON bc.organization_id = wi.organization_id
  LEFT JOIN usage_rollup ur ON ur.organization_id = wi.organization_id
  LEFT JOIN invoice_rollup ir ON ir.organization_id = wi.organization_id
  ORDER BY
    COALESCE(ur.total_sellton_cost, 0) DESC,
    COALESCE(ir.invoice_total, 0) DESC,
    COALESCE(o.name, wi.organization_id);
$$;

COMMENT ON FUNCTION public.backoffice_billing_workspace_rollup_v1(timestamptz, timestamptz) IS
  'Fast Backoffice /billing workspace rollup. Returns one row per workspace for the selected period without transferring daily/provider usage aggregates to Backoffice.';

REVOKE ALL ON FUNCTION public.backoffice_billing_workspace_rollup_v1(timestamptz, timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.backoffice_billing_workspace_rollup_v1(timestamptz, timestamptz) FROM anon;
REVOKE ALL ON FUNCTION public.backoffice_billing_workspace_rollup_v1(timestamptz, timestamptz) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.backoffice_billing_workspace_rollup_v1(timestamptz, timestamptz) TO service_role;
