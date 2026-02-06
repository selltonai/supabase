-- Add deep_research_v2 column to companies table
-- This column stores comprehensive deep research results from Perplexity's sonar-deep-research model
-- The research includes all company details: website, LinkedIn profile, industry, location, etc.

ALTER TABLE companies 
ADD COLUMN IF NOT EXISTS deep_research_v2 JSONB DEFAULT NULL;

-- Add index for querying by deep research V2 data
CREATE INDEX IF NOT EXISTS idx_companies_deep_research_v2 
ON companies USING GIN (deep_research_v2);

-- Add comment explaining the structure
COMMENT ON COLUMN companies.deep_research_v2 IS 'Comprehensive deep research results from Perplexity sonar-deep-research model. Contains full research report with citations, search results, and comprehensive analysis of the company including all available details from website, LinkedIn, industry information, etc.';




