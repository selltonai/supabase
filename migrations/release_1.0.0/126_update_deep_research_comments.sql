-- Update comments for deep research settings to include 'none' provider option
COMMENT ON COLUMN deep_research_settings.selected_providers IS 'Array of selected providers: none, exa, perplexity. Use "none" to disable deep research entirely';
COMMENT ON COLUMN deep_research_settings.selected_research_types IS 'Array of selected research types: company_overview, funding_history, recent_news, competitive_landscape, growth_signals, icp_analysis. Empty array when provider is "none"';
