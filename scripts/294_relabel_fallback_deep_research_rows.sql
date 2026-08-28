-- KAN-294: relabel deep_research rows produced by a silent grok->gemini fallback.
--
-- Background: before the F3 fix, _annotate_research_result stamped
-- effective_provider='grok' onto rows that actually ran the Gemini legacy flow
-- (fallback_from='grok', research_flow='legacy'). Those rows poisoned the V3
-- freshness cache for up to FRESH_RESEARCH_MAX_AGE_DAYS=30, so fixing the xAI
-- key alone did not re-research already-touched companies.
--
-- The F6 cache guard already makes these rows a cache miss for grok campaigns
-- even without this backfill. This script additionally corrects historical
-- provenance so usage analytics and DB inspection are truthful.
--
-- Usage analytics history is stored in usage rows at write time and is NOT
-- retroactively fixed by this script — accept that, note in release comms.
--
-- Run order: (1) snapshot, (2) preview scope, (3) relabel. Idempotent: the
-- WHERE clause only matches rows that still claim grok but ran legacy gemini.

-- 0) snapshot — keep a backup of the rows we are about to touch.
CREATE TABLE IF NOT EXISTS _backup_deep_research_fallback_20260826 AS
SELECT id, deep_research FROM companies
WHERE deep_research->>'fallback_from' = 'grok';

-- 1) preview scope — run this SELECT first and record the count.
SELECT count(*) AS poisoned_rows
FROM companies
WHERE deep_research->>'fallback_from' = 'grok'
  AND deep_research->>'research_flow' = 'legacy';

-- 2) relabel — effective_provider -> what actually ran (gemini), at both the
--    top level and inside research_metadata.
UPDATE companies
SET deep_research = jsonb_set(
        jsonb_set(deep_research, '{effective_provider}', '"gemini"', true),
        '{research_metadata,effective_provider}', '"gemini"', true)
WHERE deep_research->>'fallback_from' = 'grok'
  AND deep_research->>'research_flow' = 'legacy';
