-- Query to investigate why companies are blocked by ICP
-- This query extracts failed filters from processing_log and icp_score

-- Option 1: Query processing_log for blocked companies
SELECT 
    c.id,
    c.name,
    c.blocked_by_icp,
    c.processing_log->>'final_status' as final_status,
    c.processing_log->>'blocked_by_icp' as log_blocked_by_icp,
    c.processing_log->>'icp_score' as log_icp_score,
    -- Extract failed filters from processing_log steps
    jsonb_path_query_array(
        c.processing_log,
        '$.steps[*] ? (@.step == "icp_scoring" || @.step == "early_block_check").data.failed_filters'
    ) as failed_filters_from_log,
    -- Extract failed filters from icp_score
    c.icp_score->'llm_analysis'->'failed_filters' as failed_filters_from_icp_score,
    c.icp_score->'reasoning'->'failed_hard_filters' as failed_filters_from_reasoning,
    c.icp_score->'reasoning'->>'hard_filter_failed' as hard_filter_failed_reason,
    -- Company data that might be relevant
    c.industry,
    c.industries,
    c.employee_count,
    c.location_country,
    c.location_city,
    c.locations,
    c.technologies,
    c.updated_at
FROM companies c
WHERE c.blocked_by_icp = TRUE
ORDER BY c.updated_at DESC
LIMIT 20;

-- Option 2: More detailed view with step-by-step breakdown
SELECT 
    c.id,
    c.name,
    c.blocked_by_icp,
    -- Processing log summary
    c.processing_log->>'processing_started_at' as started_at,
    c.processing_log->>'processing_completed_at' as completed_at,
    c.processing_log->>'final_status' as final_status,
    -- Find the ICP scoring step
    (
        SELECT jsonb_agg(step)
        FROM jsonb_array_elements(c.processing_log->'steps') step
        WHERE step->>'step' IN ('icp_scoring', 'early_block_check')
    ) as icp_scoring_steps,
    -- Extract all failed filters
    COALESCE(
        c.icp_score->'llm_analysis'->'failed_filters',
        c.icp_score->'reasoning'->'failed_hard_filters',
        '[]'::jsonb
    ) as all_failed_filters,
    -- Company attributes
    jsonb_build_object(
        'industry', c.industry,
        'industries', c.industries,
        'employee_count', c.employee_count,
        'location_country', c.location_country,
        'location_city', c.location_city,
        'technologies', c.technologies
    ) as company_attributes
FROM companies c
WHERE c.blocked_by_icp = TRUE
ORDER BY c.updated_at DESC
LIMIT 10;

-- Option 3: Summary of most common blocking reasons
SELECT 
    failed_filter,
    COUNT(*) as blocked_count
FROM (
    SELECT 
        c.id,
        -- Extract failed filters from various sources
        COALESCE(
            jsonb_array_elements_text(c.icp_score->'llm_analysis'->'failed_filters'),
            jsonb_array_elements_text(c.icp_score->'reasoning'->'failed_hard_filters'),
            ARRAY[c.icp_score->'reasoning'->>'hard_filter_failed']
        ) as failed_filter
    FROM companies c
    WHERE c.blocked_by_icp = TRUE
        AND (
            c.icp_score->'llm_analysis'->'failed_filters' IS NOT NULL
            OR c.icp_score->'reasoning'->'failed_hard_filters' IS NOT NULL
            OR c.icp_score->'reasoning'->>'hard_filter_failed' IS NOT NULL
        )
) subq
WHERE failed_filter IS NOT NULL
GROUP BY failed_filter
ORDER BY blocked_count DESC;







