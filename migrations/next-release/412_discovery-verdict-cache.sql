-- Gate F4 (selltonai-modal feat/gate-f4, Borce 2026-10-27, plan PLAN_GATE_COMPANIES_F4_2026_10_27.md).
--
-- 1. discovery_verdict_cache: what the discovery gate already worked out, so a second press of
--    Find companies in the wizard neither pays AI Ark again nor judges the same companies again.
--      kind 'verdict': one company's website check and judgement for one play, keyed by the
--                      company and a hash of the play's judge inputs (brief, people, examples,
--                      sender, prompt version); an edited brief or a new prompt misses the cache.
--                      Kept 7 days.
--      kind 'page':    one AI Ark lookalike page for one lookalike company and one set of
--                      filters. Kept 24 hours.
--    Support only, never shown to customers.
-- 2. discovery_rejections.prompt_version: the judge prompt that made a market rejection, so a
--    rejection made under an older prompt stops counting when the prompt changes. Website
--    rejections (dead, social only, no website) and competitors keep counting for 30 days.
--
-- Additive only. The Modal code runs without these (it logs and goes on), so the order of the
-- deploys does not matter. Rollback: rollback/412_discovery-verdict-cache.rollback.sql

CREATE TABLE IF NOT EXISTS public.discovery_verdict_cache (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id text NOT NULL REFERENCES public.organization(id) ON DELETE CASCADE,
  campaign_id uuid,
  kind text NOT NULL CHECK (kind IN ('verdict', 'page')),
  cache_key text NOT NULL,
  payload jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT discovery_verdict_cache_key_unique UNIQUE (organization_id, kind, cache_key)
);

COMMENT ON TABLE public.discovery_verdict_cache IS
  'Discovery gate cache (support only): kind verdict = one company judged for one play (7 days), kind page = one AI Ark lookalike page (24 hours). Written and read by selltonai-modal discovery_gate.';

CREATE INDEX IF NOT EXISTS discovery_verdict_cache_created_idx
  ON public.discovery_verdict_cache (created_at);
CREATE INDEX IF NOT EXISTS discovery_verdict_cache_campaign_idx
  ON public.discovery_verdict_cache (campaign_id);

ALTER TABLE public.discovery_verdict_cache ENABLE ROW LEVEL SECURITY;
-- No policies on purpose: the service role (Modal) reads and writes; browser keys see nothing.

ALTER TABLE public.discovery_rejections
  ADD COLUMN IF NOT EXISTS prompt_version text;

COMMENT ON COLUMN public.discovery_rejections.prompt_version IS
  'Judge prompt version (market_fit_service.PROMPT_VERSION) of a market rejection; null for website and memory rejections and for rows before gate F4';
