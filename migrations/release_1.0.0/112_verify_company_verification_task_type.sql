-- Description: Verify that company_verification task type was added successfully
-- This runs after the enum modification has been committed

-- Verify the enum now includes the new value
SELECT unnest(enum_range(NULL::task_type)) as task_type_values; 