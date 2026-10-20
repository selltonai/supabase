-- Discovery gate v2 (selltonai-modal feat/discovery-gate-v2, Borce 2026-10-19).
--
-- companies.discovery_gate holds the gate's judgement of a company for the campaign that found
-- it, and the "Why this company" review card:
--   {decision, reason_code, reason, website{kind,status,error,final_url,title},
--    description_is_label, market_fit{verdict,confidence,what_they_are,campaign_market,reason,
--    competitor,competitor_confidence,brief_excludes,...}, detail, technologies_matched[],
--    campaign_id, judged_at, adjacent_policy,
--    card{what, why, fit ("direct"|"related"|null), difference, tech, facts, generated_at, model}}
--
-- Written by the discovery cron right after it saves a company (so processing never judges it
-- a second time) and by V3 when it judges a company itself; the card is added when the review
-- task is created. Read by the frontend review card (CompanyAnalysisTab) and by the per-campaign
-- related-company learning.
--
-- Additive only. The Modal code runs without it (it logs and goes on), so deploy order is free.
-- Rollback: rollback/410_companies-discovery-gate-verdict.rollback.sql

ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS discovery_gate jsonb;

COMMENT ON COLUMN public.companies.discovery_gate IS
  'Discovery gate verdict for the campaign that found the company, and the review card text (selltonai-modal discovery_gate, review_card_service)';
