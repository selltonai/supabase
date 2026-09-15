-- KAN-305 E3: provenance for verified AI Ark company resolution.
-- Raw staff/financial facts remain in the existing b2b_result JSONB profile.
ALTER TABLE public.companies ADD COLUMN IF NOT EXISTS enrichment_source text;
ALTER TABLE public.companies ADD COLUMN IF NOT EXISTS ai_ark_company_id text;
COMMENT ON COLUMN public.companies.enrichment_source IS 'Provider of the verified company profile; AI Ark resolver writes ai_ark.';
COMMENT ON COLUMN public.companies.ai_ark_company_id IS 'AI Ark company identity verified against the supplied domain or LinkedIn URL and company name.';
