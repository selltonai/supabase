-- Backfill missing usage pricing for AI Ark similar-company and Icypeas rows.
--
-- What changed:
--   - Recalculates uninvoiced zero-cost AI Ark similar-company usage rows.
--   - Recalculates uninvoiced zero-cost Icypeas email-finder usage rows.
--
-- Dependent projects:
--   - selltonai-modal: new pricing config now writes these rows with costs.
--   - selltonai: usage analytics reads stored public.usage costs.
--   - backoffice: billing pages read stored public.usage costs.
--
-- Application code:
--   - Deploy with the matching selltonai-modal pricing config update.
--   - Already-invoiced rows are intentionally not changed here; paid invoices
--     require manual credit/debit handling outside this migration.

WITH candidate_usage AS (
  SELECT
    u.id,
    u.provider,
    u.model_name,
    COALESCE(u.api_calls, 0)::numeric AS api_calls,
    COALESCE(u.output_tokens, 0)::numeric AS output_tokens,
    md.metadata
  FROM public.usage u
  CROSS JOIN LATERAL (
    SELECT public.usage_metadata_object(u.metadata) AS metadata
  ) md
  WHERE u.invoice_id IS NULL
    AND (COALESCE(u.original_cost, 0) = 0 OR COALESCE(u.sellton_cost, 0) = 0)
    AND (
      (
        u.provider = 'ai_ark'
        AND (
          u.model_name = 'ai-ark-similar_companies'
          OR COALESCE(md.metadata->>'action', '') = 'similar_companies'
        )
      )
      OR (
        u.provider = 'icypeas'
        AND COALESCE(u.model_name, '') LIKE 'icypeas%'
      )
    )
),
priced_usage AS (
  SELECT
    id,
    provider,
    model_name,
    metadata,
    CASE
      WHEN provider = 'ai_ark' THEN COALESCE(
        NULLIF(CASE WHEN COALESCE(metadata->>'billable_units', '') ~ '^[0-9]+(\.[0-9]+)?$' THEN (metadata->>'billable_units')::numeric END, 0),
        NULLIF(CASE WHEN COALESCE(metadata->>'profiles_returned', '') ~ '^[0-9]+(\.[0-9]+)?$' THEN (metadata->>'profiles_returned')::numeric END, 0),
        NULLIF(CASE WHEN COALESCE(metadata->>'total_credits', '') ~ '^[0-9]+(\.[0-9]+)?$' THEN (metadata->>'total_credits')::numeric / 0.5 END, 0),
        NULLIF(output_tokens / 0.5, 0),
        NULLIF(api_calls, 0)
      )
      ELSE COALESCE(
        NULLIF(CASE WHEN COALESCE(metadata->>'found_emails', '') ~ '^[0-9]+(\.[0-9]+)?$' THEN (metadata->>'found_emails')::numeric END, 0),
        NULLIF(CASE WHEN COALESCE(metadata->>'billable_units', '') ~ '^[0-9]+(\.[0-9]+)?$' THEN (metadata->>'billable_units')::numeric END, 0),
        NULLIF(output_tokens, 0),
        NULLIF(api_calls, 0)
      )
    END AS billable_units
  FROM candidate_usage
)
UPDATE public.usage u
SET
  original_cost = ROUND(
    p.billable_units * CASE WHEN p.provider = 'ai_ark' THEN 0.0135 ELSE 0.02 END,
    6
  ),
  sellton_cost = ROUND(
    p.billable_units * CASE WHEN p.provider = 'ai_ark' THEN 0.0405 ELSE 0.03 END,
    6
  ),
  original_pricing = CASE
    WHEN p.provider = 'ai_ark' THEN jsonb_build_object(
      'model_id', 'ai-ark-similar_companies',
      'provider', 'ai_ark',
      'provider_type', 'credit_based',
      'credits_per_profile', 0.5,
      'cost_per_credit', 0.027
    )
    ELSE jsonb_build_object(
      'model_id', 'icypeas-email-finder',
      'provider', 'icypeas',
      'provider_type', 'request_based',
      'cost_per_request', 0.02
    )
  END,
  sellton_pricing = CASE
    WHEN p.provider = 'ai_ark' THEN jsonb_build_object(
      'model_id', 'ai-ark-similar_companies',
      'provider', 'ai_ark',
      'provider_type', 'credit_based',
      'credits_per_profile', 0.5,
      'cost_per_profile_usd', 0.0405,
      'cost_per_credit', 0.027
    )
    ELSE jsonb_build_object(
      'model_id', 'icypeas-email-finder',
      'provider', 'icypeas',
      'provider_type', 'request_based',
      'cost_per_request', 0.03
    )
  END,
  metadata = p.metadata || jsonb_build_object(
    'billing_adjustment', 'backfill-ai-ark-icypeas-pricing',
    'billing_adjusted_at', NOW(),
    'backfilled_billable_units', p.billable_units
  )
FROM priced_usage p
WHERE u.id = p.id
  AND p.billable_units > 0;
