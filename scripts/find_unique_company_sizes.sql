-- Find all unique LinkedIn company size values in the database
-- Run this query to see what size ranges LinkedIn provides

SELECT 
    size,
    COUNT(*) as company_count
FROM companies 
WHERE size IS NOT NULL
GROUP BY size
ORDER BY company_count DESC;

-- Also show the mapping between size string and employee_count (to find mismatches)
-- This helps identify data quality issues

SELECT 
    size,
    employee_count,
    COUNT(*) as count
FROM companies 
WHERE size IS NOT NULL
GROUP BY size, employee_count
ORDER BY size, employee_count;

