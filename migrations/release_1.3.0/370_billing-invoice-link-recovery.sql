-- Owners: Supabase and selltonai-modal. Consumers: selltonai and Backoffice.
-- Apply before the Modal billing recovery release. Existing invoices require
-- explicit reconciliation; only newly created invoices enter automatic recovery.
ALTER TABLE public.billing_invoices
  ADD COLUMN IF NOT EXISTS usage_link_state text NOT NULL DEFAULT 'legacy'
  CHECK (usage_link_state IN ('legacy', 'pending', 'awaiting_payment', 'linked'));

ALTER TABLE public.billing_invoices
  ADD COLUMN IF NOT EXISTS usage_link_attempted_at timestamptz;

CREATE INDEX IF NOT EXISTS idx_billing_invoices_usage_link_recovery
  ON public.billing_invoices (usage_link_attempted_at NULLS FIRST, created_at)
  WHERE usage_link_state IN ('pending', 'awaiting_payment');

-- invoice_id does not contribute to analytics. Do not subtract/reinsert all
-- rollups when billing merely attaches a usage row to its invoice.
DROP TRIGGER IF EXISTS usage_analytics_projection_before_update ON public.usage;
CREATE TRIGGER usage_analytics_projection_before_update
BEFORE UPDATE ON public.usage
FOR EACH ROW
WHEN ((to_jsonb(NEW) - 'invoice_id') IS DISTINCT FROM (to_jsonb(OLD) - 'invoice_id'))
EXECUTE FUNCTION public.sync_usage_analytics_projection();

-- Aggregate with the same [start, end) timestamps used for invoice linkage.
-- The previous date-only view included the next day's usage at weekly cutoffs.
CREATE OR REPLACE FUNCTION public.billing_usage_for_period_v1(p_organization_id text, p_start timestamptz, p_end timestamptz, p_only_uninvoiced boolean DEFAULT true)
RETURNS TABLE(service text, user_id text, total_tokens bigint, total_sellton_cost numeric)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path = public
AS $$
  SELECT u.metadata ->> 'service', u.user_id,
         sum(coalesce(u.total_tokens, 0))::bigint,
         sum(coalesce(u.sellton_cost, 0))
  FROM public.usage u
  WHERE u.organization_id = p_organization_id
    AND u.created_at >= p_start AND u.created_at < p_end
    AND (NOT p_only_uninvoiced OR u.invoice_id IS NULL)
  GROUP BY u.metadata ->> 'service', u.user_id
$$;

REVOKE ALL ON FUNCTION public.billing_usage_for_period_v1(text, timestamptz, timestamptz, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.billing_usage_for_period_v1(text, timestamptz, timestamptz, boolean) TO service_role;
