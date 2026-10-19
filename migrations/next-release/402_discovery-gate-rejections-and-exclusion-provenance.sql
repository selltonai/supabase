-- Discovery gate (selltonai-modal feat/discovery-gate, Borce 2026-10-17): reject AI Ark lookalike
-- records before they are saved as companies, and put detected competitors on the exclusion list.
--
-- 1. discovery_rejections: what the gate rejected, for support and tuning only. Never shown to
--    customers. The gate also reads it so a re-fetched page is not judged twice (30 days).
-- 2. organization_icp_linkedin_urls: where an entry came from, so the settings page can label
--    "Added by Sellton: competitor" and the customer can remove it.
--
-- Additive only. The Modal code runs without these (it logs and goes on), so the order of the
-- two deploys does not matter. Rollback: rollback/402_discovery-gate-rejections-and-exclusion-provenance.rollback.sql

ALTER TABLE public.organization_icp_linkedin_urls
  ADD COLUMN IF NOT EXISTS source text NOT NULL DEFAULT 'manual',
  ADD COLUMN IF NOT EXISTS reason text,
  ADD COLUMN IF NOT EXISTS source_company_id uuid,
  ADD COLUMN IF NOT EXISTS source_campaign_id uuid;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'organization_icp_linkedin_urls_source_check'
  ) THEN
    ALTER TABLE public.organization_icp_linkedin_urls
      ADD CONSTRAINT organization_icp_linkedin_urls_source_check
      CHECK (source IN ('manual', 'bulk_upload', 'competitor_auto', 'self', 'onboarding'));
  END IF;
END $$;

COMMENT ON COLUMN public.organization_icp_linkedin_urls.source IS
  'manual (settings page), bulk_upload, competitor_auto (the discovery gate or the scorer found a direct competitor), self (the workspace''s own company), onboarding';
COMMENT ON COLUMN public.organization_icp_linkedin_urls.reason IS
  'Plain-words reason for an entry Sellton added; shown on the settings page';

CREATE TABLE IF NOT EXISTS public.discovery_rejections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  campaign_id uuid,
  seed_company_id uuid,
  ai_ark_id text,
  name text,
  website text,
  linkedin_url text,
  reason_code text NOT NULL,
  verdict jsonb,
  mode text NOT NULL DEFAULT 'enforce',
  created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.discovery_rejections IS
  'Records the discovery gate rejected before saving (support only). reason_code: no_website, dead_website, different_market, adjacent, unknown, low_confidence, competitor, previously_rejected. mode: log (would have been rejected) or enforce.';

CREATE INDEX IF NOT EXISTS discovery_rejections_campaign_created_idx
  ON public.discovery_rejections (campaign_id, created_at DESC);
CREATE INDEX IF NOT EXISTS discovery_rejections_org_created_idx
  ON public.discovery_rejections (organization_id, created_at DESC);

ALTER TABLE public.discovery_rejections ENABLE ROW LEVEL SECURITY;
-- No policies on purpose: the service role (Modal) reads and writes; browser keys see nothing.
