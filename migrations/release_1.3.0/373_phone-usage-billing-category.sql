-- Keep Airscale phone usage in the phone invoice category, including older
-- rows written by company_contact_service before its producer was corrected.
-- Consumers: selltonai-modal billing and selltonai invoice display.
-- Deploy with the Modal phone tracking fix; the RPC signature is unchanged.
-- Paid invoices and stored invoice line_items are not modified.

CREATE OR REPLACE FUNCTION public.billing_usage_for_period_v1(p_organization_id text, p_start timestamptz, p_end timestamptz, p_only_uninvoiced boolean DEFAULT true)
RETURNS TABLE(service text, user_id text, total_tokens bigint, total_sellton_cost numeric)
LANGUAGE sql STABLE SECURITY INVOKER
SET search_path = public
AS $$
  WITH categorized_usage AS (
    SELECT
      CASE
        WHEN u.provider = 'airscale'
          AND (
            u.metadata ->> 'action' = 'phone_finder'
            OR u.model_name LIKE 'airscale-phone%'
          ) THEN 'phone_discovery_service'
        ELSE u.metadata ->> 'service'
      END AS billing_service,
      u.user_id,
      u.total_tokens,
      u.sellton_cost
    FROM public.usage u
    WHERE u.organization_id = p_organization_id
      AND u.created_at >= p_start AND u.created_at < p_end
      AND (NOT p_only_uninvoiced OR u.invoice_id IS NULL)
  )
  SELECT billing_service, categorized_usage.user_id,
         sum(coalesce(total_tokens, 0))::bigint,
         sum(coalesce(sellton_cost, 0))
  FROM categorized_usage
  GROUP BY billing_service, categorized_usage.user_id
$$;

REVOKE ALL ON FUNCTION public.billing_usage_for_period_v1(text, timestamptz, timestamptz, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.billing_usage_for_period_v1(text, timestamptz, timestamptz, boolean) TO service_role;
